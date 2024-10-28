#!/usr/bin/env bash
cs_endpoint=${CS_ENDPOINT:-"https://server-url"}
cs_username=${CS_USERNAME:-"user-name"}
cs_password=${CS_PASSWORD:-"passowrd"}

solr_endpoint=${SOLR_ENDPOINT:-"https://solr-url"}

# Solr queries for draft and published content
solr_query_endpoint_draft="${solr_endpoint}/solr/editorial/select?fl=objectid&indent=true&q.op=OR&q=contenttype%3Astoryline%20AND%20state%3Adraft%20AND%20publication%3Atomorrow-online&start=${START:-0}&rows=${ROWS:-20}&wt=json"
solr_query_endpoint_published="${solr_endpoint}/solr/editorial/select?fl=objectid&indent=true&q.op=OR&q=contenttype%3Astoryline%20AND%20state%3Apublished%20AND%20publication%3Atomorrow-online&start=${START:-0}&rows=${ROWS:-20}&wt=json"

solr_query_endpoint_for_section="${solr_endpoint}/solr/editorial/select?fl=objectid&q.op=OR&q=contenttype%3Acom.escenic.section%20AND%20state%3Apublished%20AND%20publication%3Atomorrow-online&wt=json&start=0&rows=2"

function print_urls() {
	for url in $1; do
		echo $url
	done
}

function get_random_urls() {
	local ARRAY=$1
	shuf -e ${ARRAY[@]} -n$2
}

function create_link_tags_for_section_page() {
  links=""
  for url in $(get_random_urls "$1" $2); do
    links="${links}<link href=\\\"${url}\\\" rel=\\\"related\\\" type=\\\"application/atom+xml; type=entry\\\"><payload xmlns=\\\"http://www.vizrt.com/types\\\" model=\\\"${cs_endpoint}/webservice/escenic/publication/tomorrow-online/model/content-summary/storyline\\\"><field name=\\\"teaserTitle\\\"/><field name=\\\"lead-text\\\"/><field name=\\\"related\\\"/></payload></link>"
  done
  echo "${links}"
}

function fetch_content() {
  curl --silent -u ${cs_username}:${cs_password} $1
}

# Fetch draft and published content separately
draft_content_urls=$(curl --silent ${solr_query_endpoint_draft} | jq -cr --arg endpoint "${cs_endpoint}" '[.response.docs[] | $endpoint + "/webservice/escenic/content/" + .objectid] | .[]')
published_content_urls=$(curl --silent ${solr_query_endpoint_published} | jq -cr --arg endpoint "${cs_endpoint}" '[.response.docs[] | $endpoint + "/webservice/escenic/content/" + .objectid] | .[]')

# Combine draft and published content into a single list
combined_content_urls=$(echo -e "${draft_content_urls}\n${published_content_urls}")

# For section page
section_urls=$(curl --silent ${solr_query_endpoint_for_section} | jq -cr --arg endpoint "${cs_endpoint}" '[.response.docs[] | $endpoint + "/webservice/escenic/section/" + .objectid] | .[]')
echo "${section_urls}"

section_page_urls=""
for url in ${section_urls}; do
  page_url=$(fetch_content "$url" | xmlstarlet sel -t -v  '//_:entry/_:link[@rel="http://www.vizrt.com/types/relation/active-page"]/@href')
  echo "$page_url"
  section_page_urls="${section_page_urls} $page_url"
done

# Desk randomly 5 items from draft and 10 from published
for url in ${section_page_urls}; do
  # Randomly select 5 content items for the top area (draft + published mixed)
  top_content=$(create_link_tags_for_section_page "$combined_content_urls" 5)
  page_content=$(fetch_content "$url" | sed -E 's,<group:area name="top">.*<group:area name="main">,<group:area name="top">'"${top_content}"'</group:area><group:area name="main">,')

  # Randomly select content items for the main area (draft + published mixed)
  random_num=$(shuf -i 15-20 -n 1)
  main_content=$(create_link_tags_for_section_page "$combined_content_urls" "${random_num}")
  page_content=$(echo "$page_content" | sed -E 's,<group:area name="main">.*</group:area>,<group:area name="main">'"${main_content}"'</group:area>,')

  # echo "${page_content}" | xmllint --format -
  echo "PUTting content to section-page: ${url}."
  curl --include -X PUT -d "${page_content}" -u "${cs_username}:${cs_password}" -H "If-Match:*" -H "Content-Type: application/atom+xml; type=entry" "${url}"
done

