with
-- recent active users with derived metrics
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)), ''), 'Unknown') as country_hint,
    (u.upvotes - u.downvotes) as net_votes,
    (extract(epoch from (timestamp '2024-10-01 12:34:56' - u.creationdate)) / 86400.0) as account_age_days,
    dense_rank() over (order by u.reputation desc, u.id) as rep_rank
  from users u
  where u.lastaccessdate > timestamp '2024-10-01 12:34:56' - interval '365 days'
),
-- posts in the last 2 years, with normalized tags and categorization
recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.title,
    p.tags,
    case when p.posttypeid = 1 then 'Question'
         when p.posttypeid = 2 then 'Answer'
         else 'Other' end as post_kind,
    coalesce(p.owneruserid, -1) as owner_id_norm,
    string_to_array(coalesce(substring(p.tags from 2 for char_length(p.tags)-2), ''), '><') as tag_arr
  from posts p
  where p.creationdate >= timestamp '2024-10-01 12:34:56' - interval '2 years'
),
-- explode tags to rows
post_tags as (
  select
    rp.id as post_id,
    lower(trim(t)) as tag_name
  from recent_posts rp,
  lateral (select unnest(rp.tag_arr) as t) u
),
-- aggregate per user activity with window functions and null logic
user_post_stats as (
  select
    ru.user_id,
    count(*) filter (where rp.post_kind = 'Question') as questions_last2y,
    count(*) filter (where rp.post_kind = 'Answer') as answers_last2y,
    avg(nullif(rp.score, 0)) as avg_score_nonzero,
    coalesce(sum(rp.viewcount), 0) as total_views,
    max(rp.creationdate) as last_post_date,
    percentile_cont(0.5) within group (order by coalesce(rp.score, 0)) as median_score,
    count(distinct pt.tag_name) as distinct_tags_used
  from recent_users ru
  left join recent_posts rp
    on rp.owneruserid = ru.user_id
  left join post_tags pt
    on pt.post_id = rp.id
  group by ru.user_id
),
-- voting behavior on those posts
user_vote_stats as (
  select
    ru.user_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started_amt,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded_amt
  from recent_users ru
  left join recent_posts rp
    on rp.owneruserid = ru.user_id
  left join votes v
    on v.postid = rp.id
  group by ru.user_id
),
-- badge distribution by class
badge_rollup as (
  select
    b.userid as user_id,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
-- recent close/lock events affecting user questions
recent_moderation as (
  select
    p.owneruserid as user_id,
    count(*) filter (where ph.posthistorytypeid in (10,14)) as closes_locks,
    count(*) filter (where ph.posthistorytypeid in (11,15)) as reopens_unlocks,
    sum(case when ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+' then 1 else 0 end) as closes_with_reason,
    min(ph.creationdate) filter (where ph.posthistorytypeid in (10,14)) as first_mod_action
  from posts p
  join posthistory ph on ph.postid = p.id
  where p.posttypeid = 1
    and ph.creationdate >= timestamp '2024-10-01 12:34:56' - interval '2 years'
  group by p.owneruserid
),
-- detect duplicate relationships and linked density for questions
link_metrics as (
  select
    rp.owneruserid as user_id,
    count(*) filter (where pl.linktypeid = 3 and rp.posttypeid = 1) as dup_marks_on_user_questions,
    count(*) filter (where pl.linktypeid = 1 and rp.posttypeid = 1) as links_on_user_questions
  from recent_posts rp
  left join postlinks pl
    on (pl.postid = rp.id or pl.relatedpostid = rp.id)
  group by rp.owneruserid
),
-- comment activity on user's posts
comment_agg as (
  select
    rp.owneruserid as user_id,
    count(*) as comments_on_user_posts,
    sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
    max(c.creationdate) as last_comment_date
  from recent_posts rp
  left join comments c on c.postid = rp.id
  group by rp.owneruserid
),
-- tag popularity alignment: top tags used by user vs global tag counts
user_top_tags as (
  select
    rp.owneruserid as user_id,
    pt.tag_name,
    count(*) as uses
  from recent_posts rp
  join post_tags pt on pt.post_id = rp.id
  group by rp.owneruserid, pt.tag_name
),
user_top_tag_ranked as (
  select
    utt.user_id,
    utt.tag_name,
    utt.uses,
    row_number() over (partition by utt.user_id order by utt.uses desc, utt.tag_name) as rn
  from user_top_tags utt
),
user_primary_tag as (
  select user_id, tag_name as primary_tag, uses as primary_tag_uses
  from user_top_tag_ranked
  where rn = 1
),
global_tag_pop as (
  select lower(t.tagname) as tag_name, sum(t.count) as global_count
  from tags t
  group by lower(t.tagname)
),
-- assemble everything and compute composite metrics
assembled as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.rep_rank,
    ru.account_age_days,
    ru.country_hint,
    ups.questions_last2y,
    ups.answers_last2y,
    ups.avg_score_nonzero,
    ups.median_score,
    ups.total_views,
    ups.last_post_date,
    ups.distinct_tags_used,
    uvs.upvotes_received,
    uvs.downvotes_received,
    uvs.bounty_started_amt,
    uvs.bounty_awarded_amt,
    br.gold_badges,
    br.silver_badges,
    br.bronze_badges,
    br.last_badge_date,
    rm.closes_locks,
    rm.reopens_unlocks,
    rm.closes_with_reason,
    rm.first_mod_action,
    lm.dup_marks_on_user_questions,
    lm.links_on_user_questions,
    ca.comments_on_user_posts,
    ca.positive_comments,
    ca.last_comment_date,
    upt.primary_tag,
    upt.primary_tag_uses,
    gtp.global_count as primary_tag_global_count,
    case
      when coalesce(ups.answers_last2y,0) + coalesce(ups.questions_last2y,0) = 0 then null
      else round(100.0 * coalesce(ups.answers_last2y,0) / nullif(coalesce(ups.answers_last2y,0)+coalesce(ups.questions_last2y,0),0), 2)
    end as answer_ratio_pct,
    coalesce(uvs.upvotes_received,0) - coalesce(uvs.downvotes_received,0) as net_votes_received,
    case
      when ru.account_age_days > 0 then round((coalesce(ups.total_views,0) / ru.account_age_days), 2)
      else null
    end as views_per_day_of_account_age,
    round(
      coalesce(ru.reputation,0)
      + 10 * coalesce(ups.questions_last2y,0)
      + 12 * coalesce(ups.answers_last2y,0)
      + 0.5 * coalesce(ups.total_views,0)
      + 5 * coalesce(uvs.upvotes_received,0)
      - 6 * coalesce(uvs.downvotes_received,0)
      + 50 * coalesce(br.gold_badges,0)
      + 20 * coalesce(br.silver_badges,0)
      + 10 * coalesce(br.bronze_badges,0)
      - 30 * coalesce(rm.closes_locks,0)
      + 15 * coalesce(rm.reopens_unlocks,0)
      + 8 * coalesce(ca.positive_comments,0)
      - 0.1 * coalesce(lm.dup_marks_on_user_questions,0)
    , 2) as composite_activity_score
  from recent_users ru
  left join user_post_stats ups on ups.user_id = ru.user_id
  left join user_vote_stats uvs on uvs.user_id = ru.user_id
  left join badge_rollup br on br.user_id = ru.user_id
  left join recent_moderation rm on rm.user_id = ru.user_id
  left join link_metrics lm on lm.user_id = ru.user_id
  left join comment_agg ca on ca.user_id = ru.user_id
  left join user_primary_tag upt on upt.user_id = ru.user_id
  left join global_tag_pop gtp on gtp.tag_name = upt.primary_tag
),
-- percentile and rank across users
scored as (
  select
    a.*,
    ntile(100) over (order by a.composite_activity_score nulls last) as activity_percentile,
    row_number() over (order by a.composite_activity_score desc nulls last, a.user_id) as activity_rank
  from assembled a
),
-- filter to interesting cohorts using set operators and correlated checks
cohort AS (
  select s.*
  from scored s
  where
    (
      -- high performers
      s.activity_percentile >= 95
      and coalesce(s.answer_ratio_pct, 0) >= 60
    )
    union all
    select s.*
    from scored s
    where
      -- rising users: low rep rank (high number) but strong recent metrics
      s.rep_rank > (select 0.8 * count(*) from scored)
      and coalesce(s.questions_last2y,0) + coalesce(s.answers_last2y,0) >= 20
      and coalesce(s.net_votes_received,0) > 50
)
select
  c.user_id,
  c.displayname,
  c.reputation,
  c.rep_rank,
  c.activity_rank,
  c.activity_percentile,
  c.composite_activity_score,
  c.answer_ratio_pct,
  c.questions_last2y,
  c.answers_last2y,
  c.total_views,
  c.net_votes_received,
  c.gold_badges,
  c.silver_badges,
  c.bronze_badges,
  c.primary_tag,
  c.primary_tag_uses,
  c.primary_tag_global_count,
  c.country_hint,
  c.last_post_date,
  c.last_comment_date,
  c.last_badge_date,
  -- complex predicate showcase: flag anomalies
  case
    when (coalesce(c.downvotes_received,0) > coalesce(c.upvotes_received,0) and c.activity_percentile >= 90)
      or (coalesce(c.closes_locks,0) > coalesce(c.reopens_unlocks,0) + 5)
      or (coalesce(c.dup_marks_on_user_questions,0) > 3 and coalesce(c.questions_last2y,0) < 5)
    then 'Anomaly'
    else 'Normal'
  end as moderation_anomaly_flag
from cohort c
where
  -- string expression with null logic (rewrite NOT ILIKE ANY to a series of ANDs for compatibility)
  coalesce(c.displayname, '') not ilike '%bot%'
  and coalesce(c.displayname, '') not ilike '%test%'
  and coalesce(c.displayname, '') not ilike '%spam%'
  and (
    -- exclude accounts with no meaningful recent interaction
    coalesce(c.questions_last2y,0) + coalesce(c.answers_last2y,0) + coalesce(c.total_views,0) > 0
  )
order by
  c.activity_rank nulls last,
  c.user_id
limit 250;