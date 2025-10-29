-- {"query": "668.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3425} 
with
-- Active users with rank and rolling vote deltas
active_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as website_normalized,
    row_number() over (order by u.reputation desc, u.id) as rep_rank,
    lag(u.reputation) over (order by u.creationdate) as prev_rep_by_join,
    lead(u.reputation) over (order by u.creationdate) as next_rep_by_join
  from users u
  where u.reputation > 0
),
-- Questions enriched with tag array and quality metrics
questions as (
  select
    p.id as q_id,
    p.owneruserid as q_owner_id,
    p.creationdate as q_created,
    p.score as q_score,
    p.viewcount as q_views,
    p.title,
    p.tags,
    case
      when p.tags is null then array[]::varchar[]
      else string_to_array(substring(p.tags from 2 for length(p.tags)-2), '><')
    end as tag_arr,
    p.acceptedanswerid,
    p.answercount
  from posts p
  where p.posttypeid = 1
),
-- Answers with per-question stats
answers as (
  select
    a.id as a_id,
    a.parentid as q_id,
    a.owneruserid as a_owner_id,
    a.score as a_score,
    a.creationdate as a_created,
    row_number() over (partition by a.parentid order by a.score desc nulls last, a.id) as a_rank_by_score,
    max(a.score) over (partition by a.parentid) as max_a_score_for_q
  from posts a
  where a.posttypeid = 2
),
-- Vote aggregates per post
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    count(*) filter (where v.votetypeid = 8) as bounty_starts,
    coalesce(sum(case when v.votetypeid in (8,9) then v.bountyamount else 0 end),0) as bounty_total
  from votes v
  group by v.postid
),
-- Comment counts per post
comment_agg as (
  select c.postid, count(*) as comment_count, max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
-- Post history signals for closures, migrations, protections
history_flags as (
  select
    ph.postid,
    bool_or(ph.posthistorytypeid = 10) as ever_closed,
    bool_or(ph.posthistorytypeid = 11) as ever_reopened,
    bool_or(ph.posthistorytypeid = 35) as migrated_away,
    bool_or(ph.posthistorytypeid = 36) as migrated_here,
    bool_or(ph.posthistorytypeid = 19) as protected_flag,
    min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_at
  from posthistory ph
  group by ph.postid
),
-- Link graph metrics (duplicates and related)
link_agg as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as related_links,
    count(distinct pl.relatedpostid) as unique_linked_posts
  from postlinks pl
  group by pl.postid
),
-- Tag popularity snapshot
tag_pop as (
  select
    t.tagname,
    t.count as tag_total_count,
    coalesce(t.ismoderatoronly, 0) as is_mod_only,
    coalesce(t.isrequired, 0) as is_required
  from tags t
),
-- Expand question tags
question_tags as (
  select
    q.q_id,
    lower(trim(t.tag)) as tag,
    q.q_score
  from questions q
  cross join lateral unnest(q.tag_arr) as t(tag)
),
-- Tag statistics on questions actually asked
observed_tag_stats as (
  select
    qt.tag,
    count(*) as q_with_tag,
    avg(qt.q_score)::numeric(12,2) as avg_q_score_with_tag
  from question_tags qt
  group by qt.tag
),
-- Combine observed tag stats with global tag table
tag_enriched as (
  select
    tp.tagname as tag,
    tp.tag_total_count,
    tp.is_mod_only,
    tp.is_required,
    coalesce(ots.q_with_tag, 0) as q_with_tag,
    coalesce(ots.avg_q_score_with_tag, 0)::numeric(12,2) as avg_q_score_with_tag
  from tag_pop tp
  left join observed_tag_stats ots
    on ots.tag = tp.tagname
),
-- Determine "fastest accepted" answers per question
accepted_answer_latency as (
  select
    q.q_id,
    q.acceptedanswerid,
    a.a_id,
    a.a_created,
    q.q_created,
    extract(epoch from (a.a_created - q.q_created))::bigint as seconds_to_accept
  from questions q
  join answers a
    on a.a_id = q.acceptedanswerid
),
-- User activity rollups
user_rollup as (
  select
    u.id as user_id,
    sum(case when p.posttypeid = 1 then 1 else 0 end) as questions_authored,
    sum(case when p.posttypeid = 2 then 1 else 0 end) as answers_authored,
    sum(coalesce(p.score,0)) as total_post_score,
    max(p.creationdate) as last_post_at
  from users u
  left join posts p
    on p.owneruserid = u.id
  group by u.id
),
-- Outlier questions by various signals using window z-scores
question_signals as (
  select
    q.q_id,
    q.q_owner_id,
    q.q_created,
    q.q_score,
    q.q_views,
    coalesce(va.net_votes,0) as net_votes,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(ca.comment_count,0) as comment_count,
    coalesce(la.duplicate_links,0) as duplicate_links,
    coalesce(la.related_links,0) as related_links,
    coalesce(la.unique_linked_posts,0) as unique_linked_posts,
    coalesce(hf.ever_closed,false) as ever_closed,
    coalesce(hf.ever_reopened,false) as ever_reopened,
    coalesce(hf.migrated_away,false) as migrated_away,
    coalesce(hf.migrated_here,false) as migrated_here,
    coalesce(hf.protected_flag,false) as protected_flag,
    avg(q.q_views) over () as avg_views,
    stddev_pop(q.q_views) over () as std_views,
    avg(coalesce(va.net_votes,0)) over () as avg_net_votes,
    stddev_pop(coalesce(va.net_votes,0)) over () as std_net_votes
  from questions q
  left join vote_agg va on va.postid = q.q_id
  left join comment_agg ca on ca.postid = q.q_id
  left join link_agg la on la.postid = q.q_id
  left join history_flags hf on hf.postid = q.q_id
),
-- Score windows by user to detect streaks
user_question_windows as (
  select
    qs.q_id,
    qs.q_owner_id,
    qs.q_created,
    qs.q_score,
    sum(qs.q_score) over (partition by qs.q_owner_id order by qs.q_created rows between 3 preceding and current row) as rolling_score_4,
    count(*) over (partition by qs.q_owner_id) as user_q_count
  from question_signals qs
),
-- Derive a complexity score mixing multiple signals
question_complexity as (
  select
    uqw.q_id,
    uqw.q_owner_id,
    uqw.q_score,
    qs.q_views,
    qs.net_votes,
    qs.comment_count,
    qs.duplicate_links,
    qs.related_links,
    case when qs.std_views > 0 then (qs.q_views - qs.avg_views) / qs.std_views else 0 end as z_views,
    case when qs.std_net_votes > 0 then (qs.net_votes - qs.avg_net_votes) / qs.std_net_votes else 0 end as z_votes,
    (coalesce(uqw.rolling_score_4,0) * 0.2) +
    (coalesce(qs.comment_count,0) * 0.1) +
    (coalesce(qs.related_links,0) * 0.05) +
    (case when qs.ever_closed then 1 else 0 end * 0.5) +
    (case when qs.migrated_here or qs.migrated_away then 0.3 else 0 end) +
    (case when qs.protected_flag then 0.4 else 0 end) +
    (least(greatest(coalesce(qs.q_views,0),0), 100000) / 100000.0) +
    (coalesce(qs.net_votes,0) / nullif((abs(coalesce(qs.net_votes,0)) + 10),0)) as complexity_score
  from user_question_windows uqw
  join question_signals qs on qs.q_id = uqw.q_id
),
-- Bring in accepted answer latency and top answer stats
answer_enrichment as (
  select
    q.q_id,
    aal.seconds_to_accept,
    a.max_a_score_for_q,
    min(case when a.a_rank_by_score = 1 then a.a_owner_id end) as top_answerer_user_id
  from questions q
  left join accepted_answer_latency aal on aal.q_id = q.q_id
  left join answers a on a.q_id = q.q_id
  group by q.q_id, aal.seconds_to_accept, a.max_a_score_for_q
),
-- Users with badges summary
badge_rollup as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold,
    sum(case when b.class = 2 then 1 else 0 end) as silver,
    sum(case when b.class = 3 then 1 else 0 end) as bronze,
    count(*) as total_badges,
    bool_or(b.tagbased = 1) as has_tag_badges
  from badges b
  group by b.userid
),
-- Identify pairs of users who frequently interact via answers to same questions
user_coparticipation as (
  select
    q_id,
    a_owner_id as user_a,
    lead(a_owner_id) over (partition by q_id order by a_score desc, a_id) as user_b
  from answers
),
user_pairs as (
  select
    up.user_a,
    up.user_b,
    count(*) as co_answers_count
  from user_coparticipation up
  where up.user_b is not null and up.user_a <> up.user_b
  group by up.user_a, up.user_b
),
-- Normalize user display names and detect likely duplicates by case/space-insensitivity
user_name_norm as (
  select
    u.id as user_id,
    lower(regexp_replace(coalesce(u.displayname,''), '\s+', '', 'g')) as norm_name
  from users u
),
likely_dupe_users as (
  select
    a.user_id as user_id_a,
    b.user_id as user_id_b,
    a.norm_name
  from user_name_norm a
  join user_name_norm b
    on a.norm_name = b.norm_name and a.user_id < b.user_id
),
-- Combine all into a final scored, filtered, windowed resultset
final as (
  select
    qc.q_id,
    qc.q_owner_id,
    au.displayname as owner_name,
    au.rep_rank,
    ur.questions_authored,
    ur.answers_authored,
    coalesce(br.total_badges,0) as owner_badges,
    qc.q_score,
    qc.q_views,
    qc.net_votes,
    qc.comment_count,
    qc.duplicate_links,
    qc.related_links,
    ae.seconds_to_accept,
    ae.max_a_score_for_q,
    ae.top_answerer_user_id,
    te.tag,
    te.tag_total_count,
    te.is_mod_only,
    te.is_required,
    te.q_with_tag,
    te.avg_q_score_with_tag,
    coalesce(up.co_answers_count,0) as top_pair_coanswers,
    case when ld.user_id_b is not null then 1 else 0 end as owner_name_dupe_flag,
    qc.z_views,
    qc.z_votes,
    round( (coalesce(qc.z_views,0) + coalesce(qc.z_votes,0))::numeric, 3) as z_mix,
    round( qc.complexity_score::numeric, 3) as complexity_score,
    rank() over (order by qc.complexity_score desc, qc.q_views desc, qc.net_votes desc, qc.q_id) as complexity_rank,
    dense_rank() over (partition by te.tag order by qc.complexity_score desc) as rank_within_tag
  from question_complexity qc
  left join answer_enrichment ae on ae.q_id = qc.q_id
  left join question_tags qt on qt.q_id = qc.q_id
  left join tag_enriched te on te.tag = qt.tag
  left join active_users au on au.user_id = qc.q_owner_id
  left join user_rollup ur on ur.user_id = qc.q_owner_id
  left join badge_rollup br on br.userid = qc.q_owner_id
  left join user_pairs up on up.user_a = qc.q_owner_id and up.user_b = ae.top_answerer_user_id
  left join likely_dupe_users ld on ld.user_id_a = qc.q_owner_id
)
-- Final selection with complex predicates, NULL logic, set operators via a UNION for two bands
select *
from final f
where
  -- Complicated predicate combining z-scores, badges, and tag properties
  (
    (f.complexity_score > 1.5 and f.z_mix > 0.5)
    or
    (f.owner_badges >= 10 and coalesce(f.is_mod_only,0) = 0 and f.rank_within_tag <= 10)
    or
    (f.seconds_to_accept is not null and f.seconds_to_accept < 3600 and f.net_votes >= 5)
  )
  and coalesce(f.tag, '') <> ''
  and not (coalesce(f.q_views,0) = 0 and coalesce(f.net_votes,0) = 0)
  and (f.owner_name_dupe_flag = 0 or f.rep_rank <= 10000)
  and (f.q_with_tag >= 5 or f.tag_total_count >= 50)
union all
select *
from final f
where
  -- Secondary band focusing on rare tags but extreme z-scores
  (
    (coalesce(f.tag_total_count,0) < 50 and f.z_views > 2.0 and f.z_votes > 1.5)
    or
    (coalesce(f.q_with_tag,0) < 3 and f.complexity_score > 2.5)
  )
  and f.rank_within_tag <= 25
order by complexity_rank, rank_within_tag, q_id
limit 500;