-- {"query": "160.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2894} 
with
-- explode tags into one row per tag per question
question_tags as (
  select p.id as question_id,
         trim(both '<>' from regexp_split_to_table(p.tags, E'\\|')) as raw_tag -- fallback split if format varies
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
),
-- normalize tags robustly using documented pattern (<tag1><tag2>...)
normalized_tags as (
  select qt.question_id,
         tagname
  from question_tags qt
  cross join lateral (
    select unnest(
      case
        when qt.raw_tag ~ '<.+>' then string_to_array(substring(qt.raw_tag from 2 for char_length(qt.raw_tag)-2), '><')
        when qt.raw_tag like '%><%' then string_to_array(qt.raw_tag, '><')
        else array[qt.raw_tag]
      end
    ) as tagname
  ) t
),
-- compute per-question aggregates including correlated subqueries for medians and counts
question_agg as (
  select q.id,
         q.title,
         q.creationdate,
         q.score,
         q.viewcount,
         q.answercount,
         q.favoritecount,
         q.owneruserid,
         q.acceptedanswerid,
         nt.tagname,
         -- top N longest words in title as a contrived string expression
         (select string_agg(word, '|' order by length(word) desc, word) from (
            select distinct regexp_replace(unnest(regexp_split_to_array(coalesce(q.title,''), '\s+')), '[^A-Za-z0-9]', '', 'g') as word
         ) w limit 5) as longest_title_words,
         -- correlated subquery: median score of answers for this question
         (select percentile_disc(0.5) within group (order by coalesce(a.score,0))
          from posts a
          where a.posttypeid = 2 and a.parentid = q.id
         )::numeric as median_answer_score,
         -- correlated subquery: count of distinct answerers excluding owner
         (select count(distinct a.owneruserid) from posts a where a.posttypeid = 2 and a.parentid = q.id and a.owneruserid is not null and a.owneruserid <> q.owneruserid) as distinct_answerers,
         -- presence of an accepted answer (boolean-ish)
         case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted,
         -- last activity relative age seconds
         extract(epoch from now() - coalesce(q.lastactivitydate, q.creationdate))::bigint as age_seconds
  from posts q
  join normalized_tags nt on nt.question_id = q.id
  where q.posttypeid = 1
),
-- per-tag aggregates including window functions and ranking
tag_stats as (
  select tagname,
         count(*) as questions,
         sum(case when has_accepted = 1 then 1 else 0 end) as accepted_count,
         avg(coalesce(score,0))::numeric(12,4) as avg_question_score,
         percentile_disc(0.5) within group (order by age_seconds) as median_age_seconds,
         -- top 3 questions by score per tag
         array_agg(id order by score desc nulls last, viewcount desc nulls last)[:3] as top3_by_score_ids,
         -- compute a volatility measure: stddev of question scores
         stddev_pop(coalesce(score,0))::numeric(12,4) as score_stddev
  from question_agg
  group by tagname
),
-- gather user statistics combining badges, posts, votes, and last activity (includes outer joins)
user_posts as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.lastaccessdate,
         count(p.id) filter (where p.posttypeid = 1) as q_count,
         count(p.id) filter (where p.posttypeid = 2) as a_count,
         sum(coalesce(p.score,0)) as total_post_score,
         avg(coalesce(p.score,0)) as avg_post_score,
         max(p.creationdate) as last_post_date
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate
),
badge_counts as (
  select b.userid,
         count(*) filter (where b.class = 1) as gold,
         count(*) filter (where b.class = 2) as silver,
         count(*) filter (where b.class = 3) as bronze,
         count(*) as total_badges
  from badges b
  group by b.userid
),
user_votes as (
  select v.userid,
         count(*) filter (where v.votetypeid = 2) as upvotes_cast,
         count(*) filter (where v.votetypeid = 3) as downvotes_cast,
         count(*) as total_votes_cast
  from votes v
  where v.userid is not null
  group by v.userid
),
user_profile as (
  select up.user_id,
         up.displayname,
         up.reputation,
         up.creationdate,
         up.lastaccessdate,
         up.q_count,
         up.a_count,
         up.total_post_score,
         up.avg_post_score,
         coalesce(bc.gold,0) as gold,
         coalesce(bc.silver,0) as silver,
         coalesce(bc.bronze,0) as bronze,
         coalesce(uv.upvotes_cast,0) as upvotes_cast,
         coalesce(uv.downvotes_cast,0) as downvotes_cast,
         coalesce(bc.total_badges,0) as total_badges,
         -- activity score: weighted combination (arbitrary) that includes NULL safe math
         (coalesce(up.reputation,0) * 0.4) + (coalesce(up.q_count,0) * 1.5) + (coalesce(up.a_count,0) * 1.2) + (coalesce(up.total_post_score,0) * 0.3) + (coalesce(bc.total_badges,0) * 2) as activity_score
  from user_posts up
  left join badge_counts bc on bc.userid = up.user_id
  left join user_votes uv on uv.userid = up.user_id
),
-- recent post links with outer joins and set operators to find interesting relations (linked vs duplicates)
linked_pairs as (
  select pl.postid, pl.relatedpostid, lt.name as linktype, pl.creationdate
  from postlinks pl
  join linktypes lt on lt.id = pl.linktypeid
),
duplicates as (
  select postid, relatedpostid from linked_pairs where lower(linktype) like '%duplicate%' union select relatedpostid as postid, postid as relatedpostid from linked_pairs where lower(linktype) like '%duplicate%'
),
linked_nonduplicate as (
  select postid, relatedpostid from linked_pairs where lower(linktype) not like '%duplicate%'
),
-- assemble per-question enriched view combining tags, tag stats, aggregated user profile for owner, and duplication status
enriched_questions as (
  select qa.*,
         ts.questions over_tag_total_questions,
         ts.avg_question_score over_tag_avg_q_score,
         ts.score_stddev over_tag_score_stddev,
         upf.displayname as owner_name,
         upf.reputation as owner_reputation,
         upf.activity_score as owner_activity_score,
         case when d.postid is not null then true else false end as has_duplicate_mark,
         ln.relatedpostid as linked_to_postid
  from question_agg qa
  left join tag_stats ts on ts.tagname = qa.tagname
  left join user_profile upf on upf.user_id = qa.owneruserid
  left join duplicates d on d.postid = qa.id
  left join linked_nonduplicate ln on ln.postid = qa.id
),
-- rank questions per tag by a composite score using window functions and complex null logic/expressions
ranked as (
  select *,
         row_number() over (partition by tagname order by
           -- composite: favor accepted, then score, then viewcount, then recency (younger better)
           (has_accepted * 1000000) + coalesce(score,0) * 1000 + coalesce(viewcount,0) + (100000 - coalesce(age_seconds,100000)) desc
         ) as tag_rank,
         dense_rank() over (partition by tagname order by coalesce(score,0) desc) as score_rank_within_tag,
         -- bucketize: hot / warm / cold using conditional expressions and null-safe checks
         case
           when has_accepted = 1 and coalesce(score,0) >= 10 and coalesce(viewcount,0) >= 1000 then 'hot'
           when coalesce(score,0) between 3 and 9 or coalesce(viewcount,0) between 200 and 999 then 'warm'
           else 'cold'
         end as heat_bucket
  from enriched_questions
)
-- final selection including set operator to combine top-of-tag and globally interesting items, formatting strings and NULL-aware functions
select *
from (
  -- Top 2 per tag
  select 'top_per_tag' as source,
         r.tagname,
         r.tag_rank,
         r.id as question_id,
         r.title,
         coalesce(r.longest_title_words,'') as longest_title_words,
         r.score,
         r.viewcount,
         r.answercount,
         r.median_answer_score,
         r.distinct_answerers,
         r.has_accepted,
         r.owneruserid,
         coalesce(r.owner_name, 'unknown') as owner_name,
         round(coalesce(r.owner_activity_score,0)::numeric,2) as owner_activity_score,
         r.heat_bucket,
         r.over_tag_total_questions,
         r.over_tag_avg_q_score,
         r.over_tag_score_stddev,
         r.has_duplicate_mark,
         coalesce(r.linked_to_postid, -1) as linked_to_postid,
         to_char(r.creationdate, 'YYYY-MM-DD"T"HH24:MI:SS') as creation_iso,
         to_char(now()-r.creationdate, 'DD "days" HH24:MI:SS') as age_label
  from ranked r
  where r.tag_rank <= 2

  union

  -- Globally interesting: hottest unanswered questions (no accepted answer, answercount = 0) with score >= 5
  select 'global_hot_unanswered' as source,
         tagname,
         null::int as tag_rank,
         id as question_id,
         title,
         coalesce(longest_title_words,'') as longest_title_words,
         score,
         viewcount,
         answercount,
         median_answer_score,
         distinct_answerers,
         has_accepted,
         owneruserid,
         coalesce(owner_name,'unknown') as owner_name,
         round(coalesce(owner_activity_score,0)::numeric,2) as owner_activity_score,
         heat_bucket,
         over_tag_total_questions,
         over_tag_avg_q_score,
         over_tag_score_stddev,
         has_duplicate_mark,
         coalesce(linked_to_postid, -1) as linked_to_postid,
         to_char(creationdate, 'YYYY-MM-DD"T"HH24:MI:SS') as creation_iso,
         to_char(now()-creationdate, 'DD "days" HH24:MI:SS') as age_label
  from ranked
  where has_accepted = 0 and answercount = 0 and coalesce(score,0) >= 5

  except

  -- exclude any questions owned by users with zero badges (set operator example)
  select 'exclude_zero_badges' as source,
         r.tagname,
         r.tag_rank,
         r.id as question_id,
         r.title,
         '' as longest_title_words,
         r.score,
         r.viewcount,
         r.answercount,
         r.median_answer_score,
         r.distinct_answerers,
         r.has_accepted,
         r.owneruserid,
         coalesce(r.owner_name,'unknown') as owner_name,
         0.0 as owner_activity_score,
         r.heat_bucket,
         r.over_tag_total_questions,
         r.over_tag_avg_q_score,
         r.over_tag_score_stddev,
         r.has_duplicate_mark,
         coalesce(r.linked_to_postid, -1) as linked_to_postid,
         to_char(r.creationdate, 'YYYY-MM-DD"T"HH24:MI:SS') as creation_iso,
         to_char(now()-r.creationdate, 'DD "days" HH24:MI:SS') as age_label
  from ranked r
  left join badge_counts bc on bc.userid = r.owneruserid
  where coalesce(bc.total_badges,0) = 0
) final
order by source, tagname nulls last, tag_rank nulls last, score desc nulls last
limit 500;