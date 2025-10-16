-- {"query": "20.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2378} 
with
-- users with activity summary and badge density
user_stats as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(u.views,0) as views,
    coalesce(u.upvotes,0) as upvotes,
    coalesce(u.downvotes,0) as downvotes,
    coalesce(b.badge_count,0) as badge_count,
    -- badge density = badges per year of account age (avoid division by zero)
    case
      when extract(epoch from now() - u.creationdate) <= 0 then null
      else (coalesce(b.badge_count,0)::numeric / greatest(extract(epoch from now() - u.creationdate)/86400.0/365.25, 0.0001))
    end as badge_density
  from users u
  left join (
    select userId, count(*) as badge_count
    from badges
    group by userId
  ) b on b.userId = u.id
),
-- questions with computed tag arrays and parsed tag tokens
questions as (
  select
    p.id,
    p.owneruserid,
    p.title,
    p.creationdate,
    p.score,
    coalesce(p.viewcount,0) as viewcount,
    p.answercount,
    p.tags,
    -- parse tags: given format "<tag1><tag2>" produce array of tag names; handle nulls
    case when p.tags is null then '{}'::text[] else regexp_split_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><') end as tag_array,
    p.acceptedanswerid
  from posts p
  where p.posttypeid = 1
),
-- answers with link to question and computed age in seconds
answers as (
  select
    p.id,
    p.parentid as questionid,
    p.owneruserid,
    p.creationdate,
    p.score,
    coalesce(p.body,'') as body,
    extract(epoch from (p.creationdate - q.creationdate)) as seconds_after_question
  from posts p
  join posts q on q.id = p.parentid and q.posttypeid = 1
  where p.posttypeid = 2
),
-- top comment per post using window functions (ties broken by score then id)
top_comments as (
  select *
  from (
    select
      c.*,
      row_number() over (partition by c.postid order by coalesce(c.score,0) desc, c.id) rn
    from comments c
  ) t
  where t.rn = 1
),
-- recent posthistory events with complex JSON extraction and correlated subquery
recent_posthist as (
  select ph.*
    , -- extract any MentionedUserIds array from JSON in Text column if present (example JSON key: "users")
      (case
         when ph.text is not null and ph.text ~ '"users"\s*:\s*\[' then
           -- crude extraction: grab digits inside the first bracketed array of "users"
           (regexp_matches(ph.text, '"users"\s*:\s*\[([0-9, ]+)\]', ''))[1]
         else null
       end) as mentioned_userids_csv
  from posthistory ph
  where ph.creationdate > now() - interval '90 days'
),
-- aggregate per-question metrics combining answers, comments, votes, links, and history
question_agg as (
  select
    q.id as questionid,
    q.owneruserid,
    q.title,
    q.creationdate,
    q.score as question_score,
    q.viewcount,
    q.answercount,
    q.tag_array,
    count(distinct a.id) as total_answers,
    -- median answer score using percentile_cont
    (case when count(a.id) > 0 then
       percentile_cont(0.5) within group (order by a.score) over (partition by q.id)
     else null end) as median_answer_score,
    max(a.score) as best_answer_score,
    min(a.score) filter (where a.score is not null) as worst_answer_score,
    sum(coalesce(c_count.comment_count,0)) as total_comments,
    sum(coalesce(v_up.upvotes,0)) as total_upvotes,
    sum(coalesce(v_down.downvotes,0)) as total_downvotes,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_links_out,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_posts_out,
    count(distinct ph.id) as recent_history_events
  from questions q
  left join answers a on a.questionid = q.id
  left join (
    select postid, count(*) as comment_count
    from comments
    group by postid
  ) c_count on c_count.postid = q.id
  left join (
    select p.id as postid,
      sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
      sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes
    from posts p
    left join votes v on v.postid = p.id
    group by p.id
  ) v_up on v_up.postid = q.id
  left join votes v on v.postid = q.id
  left join postlinks pl on pl.postid = q.id
  left join posthistory ph on ph.postid = q.id and ph.creationdate > now() - interval '90 days'
  group by q.id, q.owneruserid, q.title, q.creationdate, q.score, q.viewcount, q.answercount, q.tag_array
),
-- compute per-tag hotness: based on recent activity, average score, and unique contributors
tag_activity as (
  select
    tag,
    count(distinct qa.questionid) as question_count,
    sum(coalesce(qa.total_answers,0)) as answers_total,
    avg(coalesce(qa.question_score,0)) as avg_q_score,
    sum(coalesce(qa.total_comments,0)) as comments_total,
    count(distinct qa.owneruserid) as unique_askers
  from question_agg qa
  cross join lateral unnest(qa.tag_array) as t(tag)
  group by tag
),
-- pick a set of candidate users: active askers with badge density and reputational weight
candidate_users as (
  select
    us.id,
    us.displayname,
    us.reputation,
    us.badge_count,
    us.badge_density,
    row_number() over (order by us.reputation desc nulls last, us.badge_density desc nulls last) rn
  from user_stats us
  where us.reputation > 1000 or us.badge_count >= 5
),
-- correlate top users with their recent posts and performance metrics (correlated subquery)
user_post_perf as (
  select
    cu.id as userid,
    cu.displayname,
    cu.reputation,
    cu.badge_count,
    cu.badge_density,
    (
      select count(*) from posts p where p.owneruserid = cu.id and p.posttypeid = 1 and p.creationdate > now() - interval '365 days'
    ) as questions_last_year,
    (
      select coalesce(avg(p.score),0) from posts p where p.owneruserid = cu.id and p.posttypeid = 2 and p.creationdate > now() - interval '365 days'
    ) as avg_answer_score_last_year,
    (
      select count(*) from comments c where c.userid = cu.id and c.creationdate > now() - interval '365 days'
    ) as comments_last_year
  from candidate_users cu
  where cu.rn <= 100
)
-- final selection: elaborate join combining many pieces; includes windowed rank, complex predicates and string ops
select
  qa.questionid,
  left(qa.title,120) as short_title,
  qa.creationdate,
  qa.viewcount,
  qa.answercount,
  qa.question_score,
  qa.total_answers,
  qa.median_answer_score,
  qa.best_answer_score,
  qa.worst_answer_score,
  qa.total_comments,
  -- tag array reassembled into CSV with fallback
  coalesce(array_to_string(qa.tag_array,','), '') as tags_csv,
  -- hotness heuristic combining views, recent history, and average answers
  ( (qa.viewcount::numeric * 0.0001) + (qa.total_answers * 0.5) + (qa.recent_history_events * 0.2) + (coalesce(qa.question_score,0) * 0.1) ) as hotness_score,
  -- complexity score: length of body in accepted answer (correlated subquery), penalize short bodies
  (select coalesce(length(a.body),0) from posts a where a.id = qa.questionid or a.parentid = qa.questionid and a.id = qa.questionid limit 1) as accepted_or_self_body_len,
  -- selective join to find top commenter name using lateral join and window function
  tc.displayname as top_commenter,
  tc.comment_score,
  -- compute rank over tag-specific hotness: partition by first tag to create varied workload
  rank() over (partition by (case when qa.tag_array is null or array_length(qa.tag_array,1) = 0 then '<<none>>' else qa.tag_array[1] end) order by ( (qa.viewcount::numeric * 0.0001) + (qa.total_answers * 0.5) + qa.recent_history_events ) desc) as tag_hot_rank,
  -- existence of duplicate links to detect canonical questions
  case when qa.duplicate_links_out > 0 then true else false end as has_duplicate_link_out,
  -- blended popularity indicator combining user reputation of asker (via left join) and question hotness
  us.reputation as asker_reputation,
  ((coalesce(us.reputation,0)::numeric * 0.00001) + ((qa.viewcount::numeric)/greatest(qa.answercount,1))) as blended_popularity
from question_agg qa
left join lateral (
  -- find top commenter for the question
  select c.userdisplayname as displayname, c.score as comment_score
  from comments c
  where c.postid = qa.questionid
  order by coalesce(c.score,0) desc, c.id
  limit 1
) tc on true
left join users us on us.id = qa.owneruserid
where
  -- complex predicate: selective but non-trivial
  (
    (qa.viewcount > 1000 and qa.total_answers >= 2 and qa.recent_history_events > 0)
    or
    (qa.question_score >= 5 and qa.best_answer_score >= 10)
    or
    (coalesce(array_to_string(qa.tag_array,','), '') ~* '^(sql|postgres|performance)\b' )
  )
  and (qa.creationdate between now() - interval '730 days' and now())
order by hotness_score desc, qa.total_answers desc, qa.questionid
limit 250;