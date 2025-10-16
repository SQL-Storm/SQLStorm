-- {"query": "215.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3868} 
with
-- explode tags for questions (PostTypeId = 1)
question_tags as (
  select
    p.id as question_id,
    lower(trim(t.tag)) as tag
  from posts p
  cross join lateral (
    select unnest(string_to_array(substring(p.tags,2,length(p.tags)-2),'><')) as tag
  ) t
  where p.posttypeid = 1 and p.tags is not null
),

-- per-user aggregates and a few derived metrics
user_stats as (
  select
    u.id,
    u.displayname,
    u.reputation,
    coalesce(sum(case when p.posttypeid = 1 then 1 else 0 end),0) as questions_posted,
    coalesce(sum(case when p.posttypeid = 2 then 1 else 0 end),0) as answers_posted,
    coalesce(count(b.id),0) as badges_total,
    coalesce(sum(case when b.class = 1 then 1 else 0 end),0) as gold_badges,
    coalesce(sum(case when b.class = 2 then 1 else 0 end),0) as silver_badges,
    coalesce(sum(case when b.class = 3 then 1 else 0 end),0) as bronze_badges,
    -- last active date and window rank of activity among users
    max(u.lastaccessdate) over () as global_last_access,
    rank() over (order by coalesce(sum(case when p.posttypeid in (1,2) then 1 else 0 end),0) desc) as activity_rank
  from users u
  left join posts p on p.owneruserid = u.id
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation
),

-- answer-level window stats: rank answers per question by score then by creation date
answer_ranks as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.creationdate,
    a.score,
    a.owneruserid,
    row_number() over (partition by a.parentid order by a.score desc nulls last, a.creationdate asc) as answer_rank_by_score,
    dense_rank() over (partition by a.parentid order by a.score desc nulls last) as answer_dense_rank
  from posts a
  where a.posttypeid = 2
),

-- per-question aggregated answer statistics (including median via ordered-set aggregate)
answer_stats as (
  select
    q.id as question_id,
    count(a.id) as answer_count,
    coalesce(avg(a.score)::numeric,0) as avg_answer_score,
    coalesce(max(a.score),0) as max_answer_score,
    coalesce(min(a.score),0) as min_answer_score,
    -- median using percentile_cont for Postgres; if no answers, returns null
    case when count(a.id) > 0 then
      percentile_cont(0.5) within group (order by a.score) over (partition by q.id)
    else null end as median_answer_score,
    count(distinct a.owneruserid) filter (where a.owneruserid is not null) as distinct_answerers
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
  group by q.id
),

-- recent edit per post: latest PostHistory entry (if any)
latest_history as (
  select distinct on (ph.postid)
    ph.postid,
    ph.id as history_id,
    ph.posthistorytypeid,
    ph.creationdate as history_date,
    left(coalesce(ph.comment, ph.text, ''), 240) as history_excerpt
  from posthistory ph
  order by ph.postid, ph.creationdate desc nulls last, ph.id desc
),

-- posts participating in link relationships, focusing on duplicates and linked posts
duplicate_links as (
  select pl.postid, pl.relatedpostid, pl.linktypeid
  from postlinks pl
  where pl.linktypeid = 3  -- duplicate relationships
),

-- union of "hot" signals: high views, many answers, or many recent comments; then remove closed posts
hot_signals as (
  select id as postid, viewcount, answercount, commentcount, lastactivitydate from posts
  where posttypeid = 1
  and (
    (viewcount is not null and viewcount > 20000)
    or (answercount is not null and answercount > 20)
    or (commentcount is not null and commentcount > 50)
  )
  union
  select id as postid, viewcount, answercount, commentcount, lastactivitydate from posts
  where posttypeid = 1 and lastactivitydate >= now() - interval '30 days'
  except
  select id as postid, viewcount, answercount, commentcount, lastactivitydate from posts
  where closeddate is not null
),

-- a deliberately complex CTE that correlates with outer queries: calculates composite vote counts with NULL logic
vote_heat as (
  select
    p.id as postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid in (4,12,16) then 1 else 0 end) as flagged_votes,
    count(v.id) as total_votes,
    -- sentiment score: normalized (up - down) / nullif(total_votes,0)
    case when count(v.id) = 0 then 0 else (sum(case when v.votetypeid = 2 then 1 else 0 end) - sum(case when v.votetypeid = 3 then 1 else 0 end))::numeric / nullif(count(v.id),0) end as sentiment
  from posts p
  left join votes v on v.postid = p.id
  group by p.id
),

-- pick top answer per question (by score, oldest in case of tie)
top_answers as (
  select ar.question_id, ar.answer_id, ar.score, ar.creationdate, ar.owneruserid
  from answer_ranks ar
  where ar.answer_rank_by_score = 1
),

-- combine many signals into a candidate set for benchmarking; include correlated subqueries
candidates as (
  select
    q.id as question_id,
    q.title,
    q.creationdate,
    q.owneruserid,
    coalesce(u.displayname, 'anonymous') as owner_name,
    q.score as question_score,
    q.viewcount,
    q.answercount,
    as_agg.answer_count,
    as_agg.avg_answer_score,
    as_agg.max_answer_score,
    as_agg.min_answer_score,
    as_agg.median_answer_score,
    as_agg.distinct_answerers,
    ta.answer_id as top_answer_id,
    ta.score as top_answer_score,
    -- time to accepted answer (if any)
    case when q.acceptedanswerid is not null then
      extract(epoch from (select a.creationdate - q.creationdate from posts a where a.id = q.acceptedanswerid))::bigint
    else null end as seconds_to_accepted,
    -- duplicate target (if duplicate link exists where this post is flagged as duplicate of another)
    dl.relatedpostid as duplicate_of_postid,
    -- concat tag list for the question (multi-row aggregate)
    (select string_agg(distinct qt.tag, ',') from question_tags qt where qt.question_id = q.id) as tag_list,
    -- recent history excerpt
    lh.history_excerpt as recent_edit_excerpt,
    vh.upvotes,
    vh.downvotes,
    vh.flagged_votes,
    vh.total_votes,
    vh.sentiment,
    -- heuristics: badge density for owner (badges per 1000 reputation, null-safe)
    case when coalesce(u.reputation,0) = 0 then null else (coalesce((select count(*) from badges b where b.userid = u.id),0)::numeric / nullif(u.reputation,0) * 1000) end as badges_per_1000_rep,
    -- correlated subquery: number of distinct users who commented on the question in last 90 days
    (select count(distinct c.userid) from comments c where c.postid = q.id and c.creationdate >= now() - interval '90 days' and c.userid is not null) as recent_commenters_90d,
    -- correlated boolean: whether any answer was posted by a high-reputation user (> 10000)
    exists (select 1 from posts a where a.parentid = q.id and a.posttypeid = 2 and a.owneruserid in (select id from users where reputation > 10000)) as has_highrep_answerer,
    -- composite score combining many signals (exercise complex arithmetic and NULL logic)
    (
      coalesce(q.score,0)::numeric * 1.5
      + coalesce(as_agg.answer_count,0) * 2.0
      + coalesce(vh.upvotes,0) * 0.75
      - coalesce(vh.downvotes,0) * 1.25
      + coalesce(as_agg.median_answer_score,0) * 1.8
      + case when ta.score is null then -2 else ta.score end * 1.2
      + case when q.acceptedanswerid is not null then 10 else 0 end
      + case when exists (select 1 from duplicate_links d where d.postid = q.id) then -15 else 0 end
      + coalesce((select count(*) from comments c where c.postid = q.id),0) * 0.2
      - coalesce(q.closeddate is not null::int,0) * 50
    ) as composite_score
  from posts q
  left join users u on u.id = q.owneruserid
  left join answer_stats as_agg on as_agg.question_id = q.id
  left join top_answers ta on ta.question_id = q.id
  left join latest_history lh on lh.postid = q.id
  left join duplicate_links dl on dl.postid = q.id
  left join vote_heat vh on vh.postid = q.id
  where q.posttypeid = 1
),

-- a filtered set based on hot signals but excluding very low-score items and demonstrating set operators
final_candidates as (
  select c.*
  from candidates c
  where c.question_id in (select postid from hot_signals)
  union
  select c2.*
  from candidates c2
  where c2.composite_score > 25
  except
  select c3.*
  from candidates c3
  where c3.viewcount < 100 and c3.answercount < 2
),

-- windowed ordering to pick a final top-N sample with tie-breakers
ranked_final as (
  select
    fc.*,
    row_number() over (
      order by fc.composite_score desc nulls last,
               fc.viewcount desc nulls last,
               fc.answer_count desc nulls last,
               fc.median_answer_score desc nulls last,
               fc.recent_commenters_90d desc nulls last
    ) as rn
  from final_candidates fc
)

select
  rf.rn,
  rf.question_id,
  left(coalesce(rf.title,'(no title)'),200) as title_snippet,
  rf.owner_name,
  rf.tag_list,
  rf.answer_count,
  rf.distinct_answerers,
  rf.top_answer_id,
  rf.top_answer_score,
  rf.median_answer_score,
  rf.seconds_to_accepted,
  rf.duplicate_of_postid,
  rf.recent_edit_excerpt,
  rf.recent_commenters_90d,
  rf.has_highrep_answerer,
  rf.upvotes,
  rf.downvotes,
  rf.flagged_votes,
  rf.total_votes,
  round(coalesce(rf.sentiment,0)::numeric,3) as sentiment_score,
  round(coalesce(rf.composite_score,0)::numeric,3) as composite_score,
  -- some string expressions and null logic to format a short summary
  concat(
    coalesce(rf.tag_list,'[no-tags]'),
    ' | views=', coalesce(rf.viewcount::text,'0'),
    ' | qscore=', coalesce(rf.question_score::text,'0'),
    ' | ans=', coalesce(rf.answer_count::text,'0')
  ) as short_summary
from ranked_final rf
where rf.rn <= 100
order by rf.composite_score desc nulls last, rf.rn asc
;