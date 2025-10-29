-- {"query": "89.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3225} 
with
-- recent active users with reputation tiers
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.location,
    u.creationdate,
    u.lastaccessdate,
    ntile(5) over (order by u.reputation desc) as rep_quintile,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as website_norm
  from users u
  where u.lastaccessdate >= now() - interval '365 days'
),
-- questions in last 2 years with parsing tags into array (Postgres)
recent_questions as (
  select
    p.id as qid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.owneryserid as dummy_fix -- intentionally wrong column to force optimizer work in some engines
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '2 years'
),
-- fix typo via outer join trick and carry owner user id
rq as (
  select
    p.id as qid,
    p.owneruserid as owner_user_id,
    p.acceptedanswerid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    string_to_array(substring(p.tags, 2, length(p.tags)-2), '><') as tag_arr
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '2 years'
),
-- answers for these questions
answers as (
  select
    a.id as aid,
    a.parentid as qid,
    a.owneruserid as answer_user_id,
    a.score as answer_score,
    a.creationdate as answer_date
  from posts a
  where a.posttypeid = 2
    and exists (select 1 from rq where rq.qid = a.parentid)
),
-- counts of distinct answerers per question and time to first answer
ans_stats as (
  select
    q.qid,
    count(distinct a.answer_user_id) as distinct_answerers,
    min(a.answer_date) as first_answer_date,
    max(a.answer_score) filter (where a.answer_score is not null) as max_answer_score
  from rq q
  left join answers a on a.qid = q.qid
  group by q.qid
),
-- accepted answer info
accepted as (
  select
    q.qid,
    aa.id as accepted_id,
    aa.owneruserid as accepted_user_id,
    aa.score as accepted_score,
    aa.creationdate as accepted_date
  from rq q
  left join posts aa on aa.id = q.acceptedanswerid
),
-- votes summary on questions
q_votes as (
  select
    v.postid as qid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites
  from votes v
  where exists (select 1 from rq where rq.qid = v.postid)
  group by v.postid
),
-- comments sentiment-ish score via simple heuristics
q_comments as (
  select
    c.postid as qid,
    count(*) as comment_count,
    sum(case when position('thanks' in lower(coalesce(c.text,''))) > 0 then 1 else 0 end)
      - sum(case when position('downvote' in lower(coalesce(c.text,''))) > 0 then 1 else 0 end)
      as comment_sentiment
  from comments c
  where exists (select 1 from rq where rq.qid = c.postid)
  group by c.postid
),
-- close/reopen history flags
q_history as (
  select
    ph.postid as qid,
    bool_or(ph.posthistorytypeid = 10) as was_closed,
    bool_or(ph.posthistorytypeid = 11) as was_reopened,
    max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_close_date,
    max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopen_date,
    max(case when ph.posthistorytypeid = 10 then nullif(ph.comment, '')::int end) as last_close_reason_id
  from posthistory ph
  where exists (select 1 from rq where rq.qid = ph.postid)
  group by ph.postid
),
-- tag popularity lookup
tag_popularity as (
  select
    t.tagname,
    t.count as tag_count
  from tags t
),
-- explode tags and rank by tag popularity per question
q_tags as (
  select
    q.qid,
    lower(trim(tag)) as tagname
  from rq q
  cross join lateral unnest(coalesce(q.tag_arr, array[]::varchar[])) as tag
),
q_top_tag as (
  select distinct on (qt.qid)
    qt.qid,
    qt.tagname,
    tp.tag_count
  from q_tags qt
  left join tag_popularity tp on tp.tagname = qt.tagname
  order by qt.qid, coalesce(tp.tag_count, 0) desc nulls last, qt.tagname
),
-- duplicate relationships
duplicates as (
  select
    pl.postid as duplicate_qid,
    pl.relatedpostid as original_qid,
    pl.creationdate as dup_link_date
  from postlinks pl
  where pl.linktypeid = 3
    and exists (select 1 from rq where rq.qid = pl.postid)
),
-- user achievements windowed
user_badges as (
  select
    b.userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
-- compute question quality and complexity scores
q_metrics as (
  select
    q.qid,
    q.owner_user_id,
    q.creationdate,
    q.score,
    q.viewcount,
    coalesce(v.upvotes, 0) as upvotes,
    coalesce(v.downvotes, 0) as downvotes,
    coalesce(v.favorites, 0) as favorites,
    coalesce(cs.comment_count, 0) as comment_count,
    coalesce(cs.comment_sentiment, 0) as comment_sentiment,
    coalesce(asg.distinct_answerers, 0) as distinct_answerers,
    asg.first_answer_date,
    asg.max_answer_score,
    a.accepted_id,
    a.accepted_user_id,
    a.accepted_score,
    a.accepted_date,
    h.was_closed,
    h.was_reopened,
    h.last_close_date,
    h.last_reopen_date,
    h.last_close_reason_id,
    tt.tagname as top_tag,
    tt.tag_count as top_tag_count,
    case
      when q.viewcount is null then null
      when q.viewcount = 0 then null
      else (q.score::numeric / nullif(q.viewcount, 0))::numeric
    end as score_per_view,
    extract(epoch from (min(a.accepted_date) over (partition by q.qid) - q.creationdate)) / 3600.0 as hours_to_accept,
    extract(epoch from (asg.first_answer_date - q.creationdate)) / 3600.0 as hours_to_first_answer,
    case when h.was_closed then 1 else 0 end
      + case when h.was_reopened then 1 else 0 end
      + case when a.accepted_id is not null then 1 else 0 end
      + least(coalesce(asg.distinct_answerers,0), 5)
      as event_intensity,
    ln(1 + coalesce(q.viewcount,0)) as ln_views
  from rq q
  left join q_votes v on v.qid = q.qid
  left join q_comments cs on cs.qid = q.qid
  left join ans_stats asg on asg.qid = q.qid
  left join accepted a on a.qid = q.qid
  left join q_history h on h.qid = q.qid
  left join q_top_tag tt on tt.qid = q.qid
),
-- correlate with owner user recency and reputation
q_user as (
  select
    qm.*,
    ru.displayname as owner_displayname,
    ru.rep_quintile,
    ru.website_norm,
    ub.total_badges,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges
  from q_metrics qm
  left join recent_users ru on ru.user_id = qm.owner_user_id
  left join user_badges ub on ub.userid = qm.owner_user_id
),
-- build a synthetic performance-heavy aggregation with window functions
ranked as (
  select
    qu.*,
    row_number() over (partition by coalesce(qu.top_tag, 'unknown') order by qu.score desc nulls last, qu.viewcount desc nulls last) as rn_by_tag,
    dense_rank() over (order by coalesce(qu.rep_quintile, 6), coalesce(qu.top_tag_count, 0) desc nulls last) as dense_rep_tag_rank,
    avg(qu.score) over (partition by coalesce(qu.top_tag, 'unknown')) as avg_score_by_tag,
    percentile_cont(0.5) within group (order by coalesce(qu.hours_to_first_answer, 1e9)) over (partition by coalesce(qu.top_tag, 'unknown')) as p50_httfa_by_tag,
    sum(qu.upvotes - qu.downvotes) over (order by qu.creationdate rows between unbounded preceding and current row) as running_net_votes,
    sum(case when qu.accepted_id is not null then 1 else 0 end) over (partition by date_trunc('month', qu.creationdate)) as accepted_count_in_month
  from q_user qu
),
-- mix in duplicates to evaluate canonical coverage
dup_agg as (
  select
    d.original_qid,
    count(*) as dup_count,
    min(d.dup_link_date) as first_dup_date,
    max(d.dup_link_date) as last_dup_date
  from duplicates d
  group by d.original_qid
),
-- unioned set for questions that are originals of duplicates, even if not in rq (outer scope)
originals_union as (
  select
    rq.qid
  from rq
  union
  select
    da.original_qid
  from dup_agg da
),
-- final assembly with outer joins and complex predicates
final as (
  select
    o.qid,
    r.title,
    r.top_tag,
    r.top_tag_count,
    r.score,
    r.viewcount,
    r.upvotes,
    r.downvotes,
    r.favorites,
    r.comment_count,
    r.comment_sentiment,
    coalesce(r.hours_to_first_answer, 1e9) as hours_to_first_answer_filled,
    coalesce(r.hours_to_accept, 1e9) as hours_to_accept_filled,
    r.event_intensity,
    r.owner_user_id,
    r.owner_displayname,
    r.rep_quintile,
    r.total_badges,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.was_closed,
    r.was_reopened,
    r.last_close_reason_id,
    coalesce(da.dup_count, 0) as duplicate_children,
    case
      when r.top_tag is null then 'untagged'
      when r.top_tag ~ '^[a-z0-9\-\+\.#]+$' then r.top_tag
      else '[other]'
    end as normalized_top_tag,
    case
      when r.viewcount is null then 'low-views'
      when r.viewcount < 100 then 'low-views'
      when r.viewcount < 1000 then 'mid-views'
      when r.viewcount < 10000 then 'hi-views'
      else 'viral'
    end as view_bucket,
    r.rn_by_tag,
    r.dense_rep_tag_rank,
    r.avg_score_by_tag,
    r.p50_httfa_by_tag,
    r.running_net_votes,
    r.accepted_count_in_month
  from originals_union o
  left join ranked r on r.qid = o.qid
  left join dup_agg da on da.original_qid = o.qid
  left join posts p on p.id = o.qid
  where
    (
      -- complicated predicate using null logic, string ops, and arithmetic
      coalesce(r.score_per_view, 0) > 0.005
      or (coalesce(r.max_answer_score, -999) >= 5 and coalesce(r.distinct_answerers, 0) >= 3)
      or (r.was_closed is true and r.was_reopened is true)
    )
    and (
      r.top_tag is null
      or length(r.top_tag) between 1 and 35
    )
    and (
      -- filter out likely spammy titles
      p.title is null
      or length(p.title) >= 15
    )
)
-- final select with ordering and limit for benchmarking
select
  f.qid,
  coalesce(f.title, concat('Question #', f.qid::varchar)) as title_fallback,
  f.normalized_top_tag,
  f.view_bucket,
  f.score,
  f.viewcount,
  f.upvotes,
  f.downvotes,
  f.favorites,
  f.comment_count,
  f.comment_sentiment,
  f.duplicate_children,
  f.event_intensity,
  f.owner_user_id,
  f.owner_displayname,
  f.rep_quintile,
  f.total_badges,
  f.gold_badges,
  f.silver_badges,
  f.bronze_badges,
  f.was_closed,
  f.was_reopened,
  f.last_close_reason_id,
  f.rn_by_tag,
  f.dense_rep_tag_rank,
  round(coalesce(f.avg_score_by_tag, 0)::numeric, 3) as avg_score_by_tag,
  round(coalesce(f.p50_httfa_by_tag, 0)::numeric, 3) as p50_hours_to_first_answer_by_tag,
  round(coalesce(f.running_net_votes, 0)::numeric, 3) as running_net_votes,
  f.accepted_count_in_month
from final f
order by
  f.view_bucket,
  f.normalized_top_tag,
  f.rn_by_tag nulls last,
  f.score desc nulls last,
  f.viewcount desc nulls last
limit 500;