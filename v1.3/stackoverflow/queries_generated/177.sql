-- {"query": "177.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2633} 
with recursive
-- explode tags into one row per post-tag
post_tags as (
  select p.id as post_id,
         lower(trim(t)) as tag
  from posts p
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(p.tags,''), 2, greatest(char_length(coalesce(p.tags,''))-2,0)), '><')) as t
  ) s
  where p.posttypeid = 1 and coalesce(p.tags,'') <> ''
),
-- compute basic aggregates per question
q_base as (
  select q.id,
         q.title,
         q.owneruserid,
         q.creationdate,
         q.acceptedanswerid,
         q.score as q_score,
         q.viewcount,
         q.answercount,
         coalesce(q.tags,'') as raw_tags,
         pt.tag
  from posts q
  left join post_tags pt on q.id = pt.post_id
  where q.posttypeid = 1
),
-- answers with some stats
answers as (
  select a.id,
         a.parentid as questionid,
         a.owneruserid,
         a.creationdate,
         a.score as a_score,
         a.body,
         a.lasteditdate
  from posts a
  where a.posttypeid = 2
),
-- fastest accepted answer delta and average answer metrics per question
q_answer_metrics as (
  select q.id as questionid,
         count(a.id) filter (where a.id is not null) as total_answers,
         avg(a.a_score) filter (where a.id is not null) as avg_answer_score,
         max(a.a_score) filter (where a.id is not null) as max_answer_score,
         min(a.a_score) filter (where a.id is not null) as min_answer_score,
         -- time in seconds to accepted answer (if exists)
         case
           when q.acceptedanswerid is not null and aa.creationdate is not null then extract(epoch from (aa.creationdate - q.creationdate))
           else null
         end as secs_to_accepted,
         -- earliest answer time
         min(extract(epoch from (a.creationdate - q.creationdate))) filter (where a.id is not null) as secs_to_first_answer
  from q_base q
  left join answers a on a.questionid = q.id
  left join answers aa on aa.id = q.acceptedanswerid
  group by q.id, q.acceptedanswerid, aa.creationdate, q.creationdate
),
-- compute per-question distinct editors (from PostHistory and LastEditorUserId)
q_editors as (
  select ph.postid,
         count(distinct ph.userid) as distinct_editors,
         count(distinct coalesce(ph.userid, q.lasteditoruserid)) as distinct_editors_with_lasteditor
  from posthistory ph
  right join posts q on q.id = ph.postid
  where q.posttypeid = 1
  group by ph.postid
),
-- commenters: top commenter per question (by count, tie-breaker by latest comment date)
commenter_rank as (
  select c.postid,
         c.userid,
         u.displayname,
         count(*) as comments_by_user,
         max(c.creationdate) as last_commented,
         row_number() over (partition by c.postid order by count(*) desc, max(c.creationdate) desc nulls last) as rn
  from comments c
  left join users u on u.id = c.userid
  group by c.postid, c.userid, u.displayname
),
top_commenters as (
  select postid, userid, displayname, comments_by_user, last_commented
  from commenter_rank
  where rn = 1
),
-- tag popularity and cross-tag popular questions
tag_stats as (
  select pt.tag,
         count(distinct pt.post_id) as questions_with_tag,
         avg(q.score) as avg_question_score,
         percentile_cont(0.5) within group (order by q.viewcount) as median_views
  from post_tags pt
  join posts q on q.id = pt.post_id
  where q.posttypeid = 1
  group by pt.tag
),
-- user performance: reputation deciles and aggregate answers/accepted rates
user_answer_stats as (
  select u.id as userid,
         u.reputation,
         ntile(10) over (order by u.reputation) as rep_decile,
         count(a.id) filter (where a.id is not null) as answers_posted,
         count(a.id) filter (where a.id is not null and a.id = p.acceptedanswerid) as accepted_count,
         -- acceptance rate guarded for divide by zero and nulls
         case when count(a.id) filter (where a.id is not null) = 0 then 0.0
              else (count(a.id) filter (where a.id is not null and a.id = p.acceptedanswerid)::numeric) /
                   nullif(count(a.id) filter (where a.id is not null),0)
         end as acceptance_rate
  from users u
  left join posts a on a.posttypeid = 2 and a.owneruserid = u.id
  left join posts p on p.acceptedanswerid = a.id
  group by u.id, u.reputation
),
-- recent activity window: rolling 30-day counts for questions and answers per user
recent_activity as (
  select u.id as userid,
         sum(case when p.posttypeid = 1 and p.creationdate >= now() - interval '30 days' then 1 else 0 end) as q_30d,
         sum(case when p.posttypeid = 2 and p.creationdate >= now() - interval '30 days' then 1 else 0 end) as a_30d
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
-- combine everything for a set of interesting tags (top 5 by questions)
top_tags as (
  select tag
  from tag_stats
  order by questions_with_tag desc nulls last
  limit 5
),
-- main candidate questions: questions that contain any of the top tags
candidate_questions as (
  select q.*,
         qam.total_answers,
         qam.avg_answer_score,
         qam.max_answer_score,
         qam.secs_to_accepted,
         qam.secs_to_first_answer,
         qe.distinct_editors_with_lasteditor,
         tc.userid as top_commenter_userid,
         tc.displayname as top_commenter_name,
         tc.comments_by_user as top_commenter_comments
  from q_base q
  left join q_answer_metrics qam on qam.questionid = q.id
  left join q_editors qe on qe.postid = q.id
  left join top_commenters tc on tc.postid = q.id
  where q.tag in (select tag from top_tags)
),
-- rank candidate questions with a composite score that uses many expressions, null logic and window functions
ranked_questions as (
  select cq.*,
         -- composite score: weighted combination with null-safe coalesce and power functions
         (
           coalesce(cq.q_score,0) * 2
           + coalesce(cq.total_answers,0) * 3
           + coalesce(cq.avg_answer_score,0) * 5
           + case when cq.secs_to_accepted is null then -50
                  else floor(1000.0 / (1 + least(cq.secs_to_accepted, 60*60*24*30))) -- favor quick accepts
             end
           + coalesce(cq.distinct_editors_with_lasteditor,0) * 4
           + (case when cq.top_commenter_comments is null then 0 else cq.top_commenter_comments * 2 end)
         ) as composite_score,
         row_number() over (partition by cq.tag order by
           (
             coalesce(cq.q_score,0) * 2
             + coalesce(cq.total_answers,0) * 3
             + coalesce(cq.avg_answer_score,0) * 5
             + case when cq.secs_to_accepted is null then -50
                    else floor(1000.0 / (1 + least(cq.secs_to_accepted, 60*60*24*30)))
               end
             + coalesce(cq.distinct_editors_with_lasteditor,0) * 4
             + (case when cq.top_commenter_comments is null then 0 else cq.top_commenter_comments * 2 end)
           ) desc,
           cq.viewcount desc nulls last,
           cq.creationdate desc
         ) as tag_rank
  from candidate_questions cq
),
-- get the top 3 per tag
top_per_tag as (
  select *
  from ranked_questions
  where tag_rank <= 3
),
-- enrich with lateral subqueries: last 3 edits and diff-like metrics (counts of posthistory types)
last_edits as (
  select tpt.id as questionid,
         edits.edits_json
  from top_per_tag tpt
  left join lateral (
    select json_agg(json_build_object('phid', ph.id, 'type', pht.name, 'user', ph.userid, 'date', ph.creationdate, 'comment', ph.comment)) as edits_json
    from posthistory ph
    left join posthistorytypes pht on pht.id = ph.posthistorytypeid
    where ph.postid = tpt.id
    order by ph.creationdate desc
    limit 5
  ) edits on true
),
-- compute some cross-set operators: find questions that are in top_per_tag but also linked as duplicates to other top questions
duplicate_links as (
  select distinct l.postid as source_q, l.relatedpostid as target_q
  from postlinks l
  where l.linktypeid = 3 -- Duplicate
    and l.postid in (select id from top_per_tag)
    and l.relatedpostid in (select id from top_per_tag)
),
-- union example: highly viewed OR highly answered among top_per_tag
high_view_or_answer as (
  select id, title, tag, 'high_view' as reason, viewcount as metric from top_per_tag where viewcount >= (select percentile_cont(0.9) within group (order by viewcount) from posts where posttypeid = 1)
  union
  select id, title, tag, 'high_answer' as reason, total_answers as metric from top_per_tag where total_answers >= 10
),
-- final selection combining everything
final_selection as (
  select t.id,
         t.title,
         t.tag,
         t.creationdate,
         t.viewcount,
         t.q_score,
         t.total_answers,
         t.avg_answer_score,
         t.max_answer_score,
         t.secs_to_accepted,
         t.secs_to_first_answer,
         t.distinct_editors_with_lasteditor,
         coalesce(u.displayname, 'unknown') as owner_name,
         u.reputation as owner_rep,
         tc.top_commenter_name,
         tc.top_commenter_comments,
         le.edits_json,
         case when dl.source_q is not null then true else false end as is_linked_duplicate_within_top,
         hv.reason as highlight_reason,
         hv.metric as highlight_metric,
         t.composite_score
  from top_per_tag t
  left join users u on u.id = t.owneruserid
  left join top_commenters tc on tc.postid = t.id
  left join last_edits le on le.questionid = t.id
  left join duplicate_links dl on dl.source_q = t.id or dl.target_q = t.id
  left join high_view_or_answer hv on hv.id = t.id
)
select *
from final_selection
order by tag, composite_score desc, viewcount desc
limit 100;