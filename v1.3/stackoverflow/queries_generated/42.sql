-- {"query": "42.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2281} 
with
-- recent activity per post with weighted score decay
RecentActivity as (
  select
    p.id,
    p.posttypeid,
    p.parentid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.title,
    p.tags,
    greatest(extract(epoch from now() - p.creationdate)::int,1) as age_seconds,
    -- time-decayed score: more recent activity contributes more
    (p.score::numeric * pow(0.85, least(365*24*3600, greatest(extract(epoch from now() - coalesce(p.lastactivitydate,p.creationdate)),0))/ (30*24*3600))) as decayed_score,
    -- normalized tag string (lowercase, remove angle brackets)
    lower(trim(both '<>' from coalesce(p.tags,''))) as norm_tags
  from posts p
  where p.posttypeid in (1,2)
),
-- aggregate votes and favorites with correlated subqueries
PostVoteAgg as (
  select
    r.id,
    r.posttypeid,
    r.parentid,
    r.owneruserid,
    r.creationdate,
    r.score,
    r.viewcount,
    r.answercount,
    r.title,
    r.tags,
    r.age_seconds,
    r.decayed_score,
    r.norm_tags,
    -- conditional aggregates via correlated subqueries to simulate realistic workload
    (select count(*) from votes v where v.postid = r.id and v.votetypeid = 2) as upvotes,
    (select count(*) from votes v where v.postid = r.id and v.votetypeid = 3) as downvotes,
    (select count(*) from votes v where v.postid = r.id and v.votetypeid = 5) as favorites,
    (select count(*) from comments c where c.postid = r.id and c.creationdate > r.creationdate) as comments_after_creation,
    -- presence of accepted answer (for questions)
    case when r.posttypeid = 1 and exists (select 1 from posts a where a.id = r.id and a.acceptedanswerid is not null) then 1 else 0 end as has_accepted
  from RecentActivity r
),
-- compute user reputation dynamics and badge counts with left joins and window functions
UserStats as (
  select
    u.id as userid,
    u.reputation,
    u.creationdate,
    u.displayname,
    u.lastaccessdate,
    -- rolling active days
    date_part('day', now() - u.creationdate)::int as account_age_days,
    -- badges breakdown
    coalesce(bc.gold,0) as gold_badges,
    coalesce(bc.silver,0) as silver_badges,
    coalesce(bc.bronze,0) as bronze_badges,
    -- last post activity
    (select max(p.lastactivitydate) from posts p where p.owneruserid = u.id) as user_last_post_activity,
    -- percentile rank of reputation among users active in last year
    pct_rank() over (order by u.reputation) as rep_pct_rank
  from users u
  left join (
    select
      b.userid,
      sum(case when b.class = 1 then 1 else 0 end) as gold,
      sum(case when b.class = 2 then 1 else 0 end) as silver,
      sum(case when b.class = 3 then 1 else 0 end) as bronze
    from badges b
    group by b.userid
  ) bc on bc.userid = u.id
),
-- join posts to user stats and enrich with link/duplicate info
EnrichedPosts as (
  select
    p.*,
    us.reputation as owner_reputation,
    us.account_age_days,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    -- count of inbound/outbound links (including duplicates)
    coalesce(pl_in.in_links,0) as inbound_links,
    coalesce(pl_out.out_links,0) as outbound_links,
    coalesce(dup.count_dup,0) as duplicate_count,
    -- whether owner is a high-rep user
    case when us.reputation >= 10000 then 1 else 0 end as high_rep_owner
  from PostVoteAgg p
  left join UserStats us on us.userid = p.owneruserid
  left join (
    select relatedpostid as pid, count(*) as in_links
    from postlinks pl
    group by relatedpostid
  ) pl_in on pl_in.pid = p.id
  left join (
    select postid as pid, count(*) as out_links
    from postlinks pl
    group by postid
  ) pl_out on pl_out.pid = p.id
  left join (
    select relatedpostid as pid, sum(case when linktypeid = 3 then 1 else 0 end) as count_dup
    from postlinks pl
    group by relatedpostid
  ) dup on dup.pid = p.id
),
-- compute tag popularity via set operations and string split (Postgres style)
TagExplode as (
  select
    ep.id,
    ep.posttypeid,
    ep.title,
    ep.norm_tags,
    regexp_split_to_table(ep.norm_tags, '><') as tag
  from EnrichedPosts ep
  where ep.norm_tags <> ''
),
TagStats as (
  select
    t.tag,
    count(*) as posts_with_tag,
    sum(case when t.posttypeid = 1 then 1 else 0 end) as questions_with_tag,
    sum(case when exists (select 1 from posts p2 where p2.id = t.id and p2.acceptedanswerid is not null) then 1 else 0 end) as accepted_count
  from TagExplode t
  group by t.tag
),
-- for each question, compute complex score combining many signals and correlated subqueries (answers, acceptance, owner rep)
QuestionSignals as (
  select
    e.id,
    e.title,
    e.owneruserid,
    e.creationdate,
    e.age_seconds,
    e.decayed_score,
    e.upvotes,
    e.downvotes,
    e.favorites,
    e.comments_after_creation,
    e.answercount,
    e.has_accepted,
    e.inbound_links,
    e.outbound_links,
    e.duplicate_count,
    e.high_rep_owner,
    -- number of answers with score >= parent.score (correlated subquery)
    (select count(*) from posts a where a.parentid = e.id and a.score >= greatest(0,e.score)) as competitive_answers,
    -- average score of answers (null-safe)
    (select avg(a.score) from posts a where a.parentid = e.id) as avg_answer_score,
    -- time to first answer in seconds
    (select extract(epoch from min(a.creationdate) - e.creationdate) from posts a where a.parentid = e.id and a.creationdate is not null) as secs_to_first_answer,
    -- popularity composite: weighted combination (floating)
    ( (coalesce(e.decayed_score,0) * 0.5)
      + (coalesce(e.upvotes,0) * 0.8)
      - (coalesce(e.downvotes,0) * 1.2)
      + (coalesce(e.favorites,0) * 1.0)
      + (case when e.has_accepted = 1 then 10 else 0 end)
      + (case when e.high_rep_owner = 1 then 2 else 0 end)
      + (coalesce(e.inbound_links,0) * 0.6)
      - (coalesce(e.duplicate_count,0) * 5)
      + (case when e.secs_to_first_answer is null then -20 else greatest(0, 20 - least(20, e.secs_to_first_answer/3600)) end)
    ) as popularity_score
  from EnrichedPosts e
  where e.posttypeid = 1
),
-- rank questions and include windowed moving averages of popularity
RankedQuestions as (
  select
    q.*,
    row_number() over (order by q.popularity_score desc NULLS LAST) as global_rank,
    dense_rank() over (partition by date_trunc('month', q.creationdate) order by q.popularity_score desc) as monthly_rank,
    avg(q.popularity_score) over (order by q.creationdate rows between 50 preceding and 50 following) as rolling_avg_101,
    median_sub.median_popularity
  from QuestionSignals q
  left join (
    -- approximate median via percentile_cont
    select id, percentile_cont(0.5) within group (order by popularity_score) over () as median_popularity
    from QuestionSignals
  ) median_sub on median_sub.id = q.id
)
select
  rq.global_rank,
  rq.id as question_id,
  rq.title,
  rq.owneruserid,
  rq.creationdate,
  rq.popularity_score,
  rq.avg_answer_score,
  rq.secs_to_first_answer,
  rq.competitive_answers,
  rq.upvotes,
  rq.downvotes,
  rq.favorites,
  rq.comments_after_creation,
  rq.answercount,
  rq.inbound_links,
  rq.outbound_links,
  rq.duplicate_count,
  rq.high_rep_owner,
  rq.monthly_rank,
  rq.rolling_avg_101,
  rq.median_popularity,
  ts.tag,
  ts.posts_with_tag,
  ts.questions_with_tag,
  ts.accepted_count,
  -- complex predicate to flag "interesting" questions
  case
    when rq.popularity_score > coalesce(rq.rolling_avg_101,0) * 1.5
      and rq.upvotes > rq.downvotes
      and rq.secs_to_first_answer is not null
      and rq.secs_to_first_answer < 24*3600
      then 'Hot'
    when rq.popularity_score < coalesce(rq.rolling_avg_101,0) * 0.4
      and rq.answercount = 0
      then 'Cold'
    else 'Normal'
  end as interest_tag
from RankedQuestions rq
-- join to tag stats picking the most frequent tag per question (if any)
left join lateral (
  select t.tag, t.posts_with_tag, t.questions_with_tag, t.accepted_count
  from TagExplode te
  join TagStats t on t.tag = te.tag
  where te.id = rq.id
  order by t.posts_with_tag desc nulls last
  limit 1
) ts on true
where rq.global_rank <= 1000
order by rq.popularity_score desc NULLS LAST, rq.global_rank;