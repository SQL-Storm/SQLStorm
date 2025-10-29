-- {"query": "540.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3661} 
with
-- Active users with activity stats
active_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as region_hint,
    u.upvotes,
    u.downvotes,
    u.views,
    (u.upvotes - u.downvotes) as net_votes,
    case when u.websiteurl ilike '%github%' then 1 else 0 end as has_github
  from users u
  where u.reputation > 0
),
-- Posts with normalized tag arrays and type flags
post_core as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.lastactivitydate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.title,
    p.tags,
    case when p.posttypeid = 1 then 1 else 0 end as is_question,
    case when p.posttypeid = 2 then 1 else 0 end as is_answer,
    string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><') as tag_arr
  from posts p
  where p.creationdate is not null
),
-- Recent window to constrain heavy calcs
recent_posts as (
  select pc.*
  from post_core pc
  where pc.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from posts)
),
-- Link/duplicate graph counts
post_link_agg as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 1) as linked_out_count,
    count(*) filter (where pl.linktypeid = 3) as dup_out_count,
    count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as dup_targets
  from postlinks pl
  group by pl.postid
),
-- Votes distribution per post using window and conditional aggs
vote_rollup as (
  select
    v.postid,
    count(*) filter (where v.votetypeid = 2) as upvotes,
    count(*) filter (where v.votetypeid = 3) as downvotes,
    count(*) filter (where v.votetypeid = 5) as favorites,
    count(*) filter (where v.votetypeid = 8) as bounties_started,
    sum(coalesce(v.bountyamount,0)) as bounty_total,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
-- First/last edit, close info per post from PostHistory with correlated extraction
history_pivots as (
  select
    ph.postid,
    min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as closed_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as reopened_at,
    max(case when ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+' then ph.comment end) as close_reason_id_text
  from posthistory ph
  group by ph.postid
),
-- Expand tags and combine with tag meta for weighting
post_tags as (
  select
    rp.id as post_id,
    lower(trim(tg.tagname)) as tag,
    tg.count as tag_global_count,
    tg.ismoderatoronly::int as is_mod_only,
    tg.isrequired::int as is_required
  from recent_posts rp
  left join lateral unnest(coalesce(rp.tag_arr, array[]::varchar[])) as t(tag) on true
  left join tags tg on lower(t.tag) = lower(tg.tagname)
  where rp.is_question = 1
),
-- Rank tags per post by global popularity to create a "rarity score"
tag_rank as (
  select
    pt.post_id,
    pt.tag,
    pt.tag_global_count,
    case when pt.tag_global_count is null or pt.tag_global_count = 0 then 1e6 else 1.0 / pt.tag_global_count end as rarity_weight,
    row_number() over (partition by pt.post_id order by coalesce(pt.tag_global_count, 2147483647)) as rarity_rank
  from post_tags pt
),
-- Summarize tag rarity per post
tag_summary as (
  select
    post_id,
    count(*) as tag_cnt,
    sum(rarity_weight) as rarity_sum,
    max(case when rarity_rank = 1 then tag end) as rarest_tag
  from tag_rank
  group by post_id
),
-- Join everything to build a per-post feature vector
post_features as (
  select
    rp.id,
    rp.owneruserid,
    rp.creationdate,
    rp.lastactivitydate,
    rp.score,
    rp.viewcount,
    rp.answercount,
    rp.commentcount,
    rp.favoritecount,
    rp.title,
    coalesce(vr.upvotes,0) as upvotes,
    coalesce(vr.downvotes,0) as downvotes,
    coalesce(vr.favorites,0) as fav_votes,
    coalesce(vr.bounties_started,0) as bounty_started,
    coalesce(vr.bounty_total,0) as bounty_total,
    vr.first_vote_at,
    vr.last_vote_at,
    coalesce(pla.linked_out_count,0) as linked_out_count,
    coalesce(pla.dup_out_count,0) as dup_out_count,
    coalesce(ts.tag_cnt,0) as tag_cnt,
    coalesce(ts.rarity_sum,0.0) as rarity_sum,
    ts.rarest_tag,
    hp.first_edit_at,
    hp.last_edit_at,
    hp.closed_at,
    hp.reopened_at,
    nullif(hp.close_reason_id_text, '')::int as close_reason_id,
    case when hp.closed_at is not null and hp.reopened_at is null then 1
         when hp.closed_at is not null and hp.reopened_at is not null and hp.reopened_at > hp.closed_at then 2
         else 0 end as close_state
  from recent_posts rp
  left join vote_rollup vr on vr.postid = rp.id
  left join post_link_agg pla on pla.postid = rp.id
  left join tag_summary ts on ts.post_id = rp.id
  left join history_pivots hp on hp.postid = rp.id
),
-- Per-user aggregates with window functions and conditional null logic
user_agg as (
  select
    au.user_id,
    count(*) filter (where pf.score is not null) as posts_seen,
    count(*) filter (where pf.answercount is not null and pf.answercount > 0) as qs_with_answers,
    sum(coalesce(pf.viewcount,0)) as total_views,
    sum(coalesce(pf.score,0)) as total_score,
    avg(nullif(pf.commentcount,0)) as avg_comments_nonzero,
    percentile_cont(0.5) within group (order by coalesce(pf.viewcount,0)) as median_views,
    max(pf.creationdate) as last_post_at,
    min(pf.creationdate) as first_post_at,
    sum(case when pf.closed_at is not null then 1 else 0 end) as closed_posts,
    sum(case when pf.dup_out_count > 0 then 1 else 0 end) as dup_flagged_posts
  from active_users au
  left join post_features pf on pf.owneruserid = au.user_id
  group by au.user_id
),
-- Badge snapshots and diversity metric
badge_agg as (
  select
    b.userid as user_id,
    count(*) as badge_count,
    count(distinct b.name) as distinct_badges,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
-- Comment activity as an additional signal
comment_agg as (
  select
    c.userid as user_id,
    count(*) as comments_made,
    coalesce(sum(c.score),0) as comment_score_sum,
    avg(c.score) as comment_score_avg,
    max(c.creationdate) as last_comment_at
  from comments c
  where c.userid is not null
  group by c.userid
),
-- Windowed ranking per user over their posts to compute momentum snapshots
post_momentum as (
  select
    pf.id as post_id,
    pf.owneruserid as user_id,
    pf.creationdate,
    pf.score,
    pf.viewcount,
    sum(coalesce(pf.score,0)) over (partition by pf.owneruserid order by pf.creationdate rows between 9 preceding and current row) as score_10post_sum,
    avg(coalesce(pf.viewcount,0)) over (partition by pf.owneruserid order by pf.creationdate rows between 9 preceding and current row) as views_10post_avg,
    count(*) over (partition by pf.owneruserid order by pf.creationdate rows between unbounded preceding and current row) as post_seq_num
  from post_features pf
  where pf.owneruserid is not null
),
-- Identify milestone posts per user (first accepted answer, highest score, etc.)
milestones as (
  select
    pm.user_id,
    min(pm.post_id) filter (where p.posttypeid = 2 and p.id in (select acceptedanswerid from posts q where q.acceptedanswerid = p.id)) as first_accepted_answer_post_id,
    max(pm.post_id) filter (where pm.score = (select max(score) from posts p2 where p2.owneruserid = pm.user_id)) as highest_score_post_id,
    min(pm.creationdate) as first_seen_post_at
  from post_momentum pm
  join posts p on p.id = pm.post_id
  group by pm.user_id
),
-- Combine user attributes
user_profile as (
  select
    au.user_id,
    au.displayname,
    au.reputation,
    au.creationdate,
    au.region_hint,
    au.net_votes,
    au.has_github,
    ua.posts_seen,
    ua.qs_with_answers,
    ua.total_views,
    ua.total_score,
    ua.avg_comments_nonzero,
    ua.median_views,
    ua.first_post_at,
    ua.last_post_at,
    ua.closed_posts,
    ua.dup_flagged_posts,
    coalesce(ba.badge_count,0) as badge_count,
    coalesce(ba.distinct_badges,0) as distinct_badges,
    coalesce(ba.gold_count,0) as gold_badges,
    coalesce(ba.silver_count,0) as silver_badges,
    coalesce(ba.bronze_count,0) as bronze_badges,
    ba.last_badge_at,
    coalesce(ca.comments_made,0) as comments_made,
    coalesce(ca.comment_score_sum,0) as comment_score_sum,
    ca.comment_score_avg,
    ca.last_comment_at,
    ms.first_accepted_answer_post_id,
    ms.highest_score_post_id,
    ms.first_seen_post_at
  from active_users au
  left join user_agg ua on ua.user_id = au.user_id
  left join badge_agg ba on ba.user_id = au.user_id
  left join comment_agg ca on ca.user_id = au.user_id
  left join milestones ms on ms.user_id = au.user_id
),
-- Build per-question difficulty-like score
question_difficulty as (
  select
    pf.id as question_id,
    pf.owneruserid as asker_id,
    pf.creationdate,
    pf.score,
    pf.viewcount,
    pf.answercount,
    coalesce(pf.upvotes - pf.downvotes, pf.score) as net_vote_proxy,
    1.0 * coalesce(pf.viewcount,0) / nullif(1 + pf.answercount, 0) as views_per_answer,
    case when pf.answercount is null or pf.answercount = 0 then 1 else 0 end as unanswered_flag,
    pf.rarity_sum,
    pf.tag_cnt,
    (coalesce(pf.rarity_sum,0) * (1 + coalesce(pf.tag_cnt,0))) as rarity_signal
  from post_features pf
  where pf.id in (select id from recent_posts where is_question = 1)
),
-- Match answers to questions with outer joins and compute answer effectiveness
answer_effect as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answerer_id,
    a.creationdate as answer_created,
    a.score as answer_score,
    a.viewcount as answer_views,
    q.score as question_score,
    q.viewcount as question_views,
    (a.score - coalesce(q.score,0)) as score_diff_vs_q,
    (a.viewcount - coalesce(q.viewcount,0)) as view_diff_vs_q
  from posts a
  left join posts q on q.id = a.parentid
  where a.posttypeid = 2
),
-- Rolling answerer performance around time
answerer_perf as (
  select
    ae.answerer_id as user_id,
    ae.answer_id,
    ae.answer_created,
    ae.answer_score,
    avg(ae.answer_score) over (partition by ae.answerer_id order by ae.answer_created rows between 4 preceding and current row) as rolling_answer_score_avg5,
    sum(case when ae.answer_score > 0 then 1 else 0 end) over (partition by ae.answerer_id order by ae.answer_created rows between 9 preceding and current row) as rolling_positive_count10
  from answer_effect ae
  where ae.answerer_id is not null
),
-- Final scoring with set operations: pick top and bottom segments and union all
scored_posts as (
  select
    qd.question_id as entity_id,
    'question' as entity_type,
    qd.creationdate as entity_created,
    qd.net_vote_proxy as primary_score,
    qd.views_per_answer as aux_metric,
    qd.rarity_signal as complexity_metric,
    qd.unanswered_flag,
    qd.asker_id as user_id
  from question_difficulty qd
  union all
  select
    ap.answer_id,
    'answer',
    ap.answer_created,
    ap.rolling_answer_score_avg5,
    ap.rolling_positive_count10,
    ap.answer_score,
    null::int,
    ap.user_id
  from answerer_perf ap
),
-- Rank within buckets for benchmarking selection
ranked as (
  select
    sp.*,
    dense_rank() over (partition by sp.entity_type order by sp.primary_score desc nulls last) as rnk_desc,
    dense_rank() over (partition by sp.entity_type order by sp.primary_score asc nulls last) as rnk_asc
  from scored_posts sp
)
select
  r.entity_type,
  r.entity_id,
  r.entity_created,
  r.primary_score,
  r.aux_metric,
  r.complexity_metric,
  r.unanswered_flag,
  r.user_id,
  up.displayname as user_displayname,
  up.reputation,
  up.region_hint,
  up.badge_count,
  up.distinct_badges,
  up.comments_made,
  -- String composition with null handling
  coalesce(up.displayname, 'User#' || r.user_id::text) || ' (' || coalesce(up.region_hint, 'N/A') || ')' as user_label,
  -- Complicated predicate projection to flag "interesting"
  case
    when r.entity_type = 'question' and coalesce(r.complexity_metric,0) > 0.02 and coalesce(r.aux_metric,0) > 500 then 'HOT-RARE'
    when r.entity_type = 'answer' and coalesce(r.aux_metric,0) >= 7 and coalesce(r.primary_score,0) >= 1 then 'CONSISTENT'
    when r.primary_score is null then 'NO-SCORE'
    else 'NORMAL'
  end as interest_bucket
from ranked r
left join user_profile up on up.user_id = r.user_id
where
  -- Include top-N and bottom-N per entity_type using set-like logic
  (
    r.rnk_desc <= 100
    or r.rnk_asc <= 100
    or (r.entity_type = 'question' and r.unanswered_flag = 1 and coalesce(r.aux_metric,0) > 1000)
  )
order by
  r.entity_type,
  r.rnk_desc nulls last,
  r.entity_created desc
limit 500;