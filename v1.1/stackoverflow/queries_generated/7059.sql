-- {"query": "7059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2198} 
with
-- top users by adjusted reputation (nonlinear penalty for downvotes, boost for views)
user_metrics as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.views,
    greatest(0, u.reputation + coalesce(sum(case when v.votetypeid=2 then 10 when v.votetypeid=3 then -25 else 0 end),0)) as adj_reputation,
    -- active score uses recency-weighted activity and badges
    (
      coalesce((extract(epoch from now() - u.lastaccessdate)/86400), 3650) -- days since last access
    ) as days_since_last_access,
    coalesce(bad.badge_score,0) as badge_score
  from users u
  left join votes v on v.userid = u.id
  left join (
    select userId,
      sum(case class when 1 then 50 when 2 then 20 when 3 then 5 else 1 end) * count(*) over (partition by userId) * 0.01 as badge_score
    from badges
    group by userid, class
  ) bad on bad.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.views, u.lastaccessdate, bad.badge_score
),
-- questions with tag array and precomputed heuristics
questions as (
  select
    p.id,
    p.owneruserid,
    p.title,
    p.tags,
    p.creationdate,
    p.viewcount,
    p.score,
    p.answercount,
    p.favoritecount,
    coalesce((p.viewcount::numeric / nullif(greatest(p.answercount,1),0)), p.viewcount) as views_per_answer,
    regexp_split_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><') as tag_list
  from posts p
  where p.posttypeid = 1
),
-- top answers with correlation to their parent question and temporal distance
answers as (
  select
    a.id,
    a.parentid,
    a.owneruserid,
    a.score,
    a.creationdate,
    a.body,
    age(a.creationdate, q.creationdate) as answer_delay,
    q.title as question_title,
    q.tags as question_tags,
    row_number() over (partition by a.parentid order by a.score desc, a.creationdate asc) as answer_rank
  from posts a
  join posts q on q.id = a.parentid and q.posttypeid = 1
  where a.posttypeid = 2
),
-- compute per-question aggregated signals (including correlated subqueries)
question_signals as (
  select
    q.id,
    q.title,
    q.tags,
    q.creationdate,
    q.viewcount,
    q.score,
    q.answercount,
    q.favoritecount,
    q.views_per_answer,
    coalesce((
      select count(*) from answers a where a.parentid = q.id and a.score > 0
    ),0) as positive_answers,
    coalesce((
      select avg(a.score) from answers a where a.parentid = q.id
    ),0) as avg_answer_score,
    coalesce((
      select min(age(a.creationdate, q.creationdate)) from answers a where a.parentid = q.id
    )::interval, '0 days') as fastest_answer_delay,
    ( -- stringy complexity: longest tag name length and concatenated brief tag signature
      select max(char_length(t)) from unnest(q.tag_list::text[]) t
    ) as max_tag_len,
    ( -- tag signature - concatenated first letters sorted
      array_to_string(
        (select array_agg(substring(t from 1 for 1) order by substring(t from 1 for 1))
         from unnest(q.tag_list::text[]) t), ''
      ) as tag_signature
  from questions q
),
-- heavy join of votes and comments for weighted engagement per post
engagement as (
  select
    p.id as postid,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 when v.votetypeid = 5 then 3 else 0 end) as vote_net,
    count(distinct c.id) as comment_count,
    sum(coalesce(v.bountyamount,0)) as bounty_total,
    -- composite engagement metric
    (coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end),0) * 2.0
     + count(distinct c.id) * 1.5
     + coalesce(sum(coalesce(v.bountyamount,0)),0) * 0.1
    ) as engagement_score
  from posts p
  left join votes v on v.postid = p.id
  left join comments c on c.postid = p.id
  group by p.id, p.posttypeid, p.owneruserid, p.creationdate
),
-- windowed ranking across combined posts for benchmarking
ranked_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.title,
    p.tags,
    e.vote_net,
    e.comment_count,
    e.bounty_total,
    e.engagement_score,
    dense_rank() over (order by e.engagement_score desc nulls last, p.score desc nulls last) as engagement_rank,
    row_number() over (partition by p.posttypeid order by e.engagement_score desc) as rank_by_type,
    ntile(10) over (order by e.engagement_score desc) as engagement_decile
  from posts p
  left join engagement e on e.postid = p.id
),
-- pick a cohort of "interesting" questions combining many signals
interesting_questions as (
  select
    qs.*,
    rp.engagement_score,
    um.adj_reputation,
    um.badge_score,
    -- composite interest score: nonlinear combining many parts
    (
      pow(greatest(coalesce(rp.engagement_score,0),0) + 1, 0.65)
      * (1 + least(coalesce(qs.avg_answer_score,0)/10.0, 1))
      * (1 + least(coalesce(um.adj_reputation,0)/10000.0, 1))
      * (1 + least(coalesce(um.badge_score,0)/100.0, 0.5))
      / nullif(1 + extract(epoch from now() - qs.creationdate)::numeric / 86400.0 / 90.0, 0)
    ) as interest_score
  from question_signals qs
  left join ranked_posts rp on rp.id = qs.id
  left join users um on um.id = qs.id -- intentionally odd join to exercise outer join nulls (will be null)
),
-- correlate questions to their most recent posthistory entry matching close/reopen etc.
recent_history as (
  select ph.postid,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11,12,13,35,36)) as last_moderation_action,
    array_agg(distinct ph.posthistorytypeid order by ph.creationdate desc) [1:5] as recent_history_types,
    max(ph.id) as last_history_id
  from posthistory ph
  group by ph.postid
),
-- assemble final heavy report with set operations and correlated subqueries
final_candidates as (
  select
    iq.id as question_id,
    iq.title,
    coalesce(iq.tags,'') as tags,
    iq.creationdate,
    iq.viewcount,
    iq.score as question_score,
    iq.answercount,
    iq.avg_answer_score,
    iq.positive_answers,
    iq.fastest_answer_delay,
    iq.max_tag_len,
    iq.tag_signature,
    iq.interest_score,
    rh.last_moderation_action,
    rh.recent_history_types,
    rp.engagement_rank,
    rp.engagement_decile,
    um.displayname as owner_name,
    um.adj_reputation as owner_adj_rep,
    um.badge_score as owner_badge_score,
    -- correlated subquery: top 3 answers' ids and authors concatenated
    (select string_agg(concat(a.id,':',coalesce(u.displayname,'<anon>'),':',a.score), ';' order by a.score desc, a.creationdate asc)
     from posts a
     left join users u on u.id = a.owneruserid
     where a.parentid = iq.id and a.posttypeid = 2
     limit 3
    ) as top_answers_summary
  from interesting_questions iq
  left join recent_history rh on rh.postid = iq.id
  left join ranked_posts rp on rp.id = iq.id
  left join users um on um.id = iq.owneruserid
)
select distinct on (fc.question_id)
  fc.question_id,
  left(fc.title, 250) as title_snippet,
  fc.tags,
  fc.creationdate,
  fc.viewcount,
  fc.question_score,
  fc.answercount,
  round(fc.avg_answer_score::numeric,2) as avg_answer_score,
  fc.positive_answers,
  fc.fastest_answer_delay,
  fc.max_tag_len,
  fc.tag_signature,
  round(fc.interest_score::numeric,6) as interest_score,
  fc.last_moderation_action,
  fc.recent_history_types,
  fc.engagement_rank,
  fc.engagement_decile,
  coalesce(fc.owner_name, '<unknown>') as owner_name,
  coalesce(fc.owner_adj_rep, 0) as owner_adj_rep,
  coalesce(fc.owner_badge_score, 0) as owner_badge_score,
  fc.top_answers_summary
from final_candidates fc
where fc.interest_score is not null
  and fc.interest_score > (
    select percentile_cont(0.75) within group (order by interest_score) from final_candidates
  )
  and not (fc.tags ilike '%discussion%' or fc.tags ilike '%meta%')
order by fc.interest_score desc, fc.viewcount desc
limit 250;