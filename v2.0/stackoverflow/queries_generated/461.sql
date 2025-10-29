-- {"query": "461.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3256} 
with
-- recent active users and their activity score
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(u.location, 'Unknown') as location,
    sum(coalesce(vu.upvotes,0)) over (partition by u.id) as upvote_sum_window
  from users u
  left join lateral (
    select 1 as upvotes
    from generate_series(1, greatest(u.upvotes,0)) gs(x)
  ) vu on true
  where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from users)
),
-- posts in the last N years with tags expanded
recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.creationdate,
    p.lastactivitydate,
    p.acceptedanswerid,
    p.parentid,
    p.title,
    lower(trim(both ' ' from t.tag)) as tag
  from posts p
  left join lateral (
    select unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tag
  ) t on p.posttypeid = 1 and p.tags is not null
  where p.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from posts)
),
-- aggregate per user KPIs
user_post_kpis as (
  select
    ru.user_id,
    count(*) filter (where rp.posttypeid = 1) as q_count,
    count(*) filter (where rp.posttypeid = 2) as a_count,
    sum(coalesce(rp.score,0)) as total_post_score,
    avg(nullif(rp.viewcount,0)) as avg_views_nonzero,
    max(rp.score) as max_post_score,
    min(rp.creationdate) as first_recent_post,
    count(distinct rp.tag) as distinct_tags_used
  from recent_users ru
  left join recent_posts rp
    on rp.owneruserid = ru.user_id
  group by ru.user_id
),
-- votes per user on their posts
user_vote_kpis as (
  select
    p.owneruserid as user_id,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
    count(*) filter (where v.votetypeid = 8) as bounties_started,
    sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_amount_total
  from posts p
  left join votes v on v.postid = p.id
  where p.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from posts)
  group by p.owneruserid
),
-- comments sentiment proxy and density
user_comment_kpis as (
  select
    p.owneruserid as user_id,
    count(c.id) as comment_count,
    avg(c.score) as avg_comment_score,
    sum(case when c.text ilike any (array['%thank%','%great%','%helpful%','%awesome%']) then 1 else 0 end) as positive_comments,
    sum(case when c.text ilike any (array['%bad%','%wrong%','%stupid%','%downvote%']) then 1 else 0 end) as negative_comments
  from posts p
  left join comments c on c.postid = p.id
  where p.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from posts)
  group by p.owneruserid
),
-- badge recency and diversity
user_badge_kpis as (
  select
    b.userid as user_id,
    count(*) as badge_count,
    count(distinct b.name) as distinct_badges,
    max(b.date) as last_badge_date,
    sum(case when b.class = 1 then 1 else 0 end) as gold_count,
    sum(case when b.class = 2 then 1 else 0 end) as silver_count,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
    sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
  from badges b
  where b.date >= (select date_trunc('year', max(date)) - interval '3 years' from badges)
  group by b.userid
),
-- closure and history signals
user_history_kpis as (
  select
    p.owneruserid as user_id,
    count(*) filter (where ph.posthistorytypeid = 10) as closes,
    count(*) filter (where ph.posthistorytypeid = 11) as reopens,
    count(*) filter (where ph.posthistorytypeid in (12,13)) as deletions_restores,
    count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied,
    count(*) filter (where ph.posthistorytypeid in (52)) as hot_network,
    count(*) filter (where ph.posthistorytypeid in (53)) as removed_hot
  from posts p
  left join posthistory ph on ph.postid = p.id
  where p.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from posts)
  group by p.owneruserid
),
-- duplicates and links
user_link_kpis as (
  select
    p.owneruserid as user_id,
    count(*) filter (where pl.linktypeid = 3 and p.posttypeid = 1) as dup_marked_questions,
    count(*) filter (where pl.linktypeid = 1) as linked_relations
  from posts p
  left join postlinks pl on pl.postid = p.id
  where p.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from posts)
  group by p.owneruserid
),
-- rolling activity windows per user
user_activity_windows as (
  select
    rp.owneruserid as user_id,
    date_trunc('month', rp.creationdate) as month_bucket,
    count(*) as posts_in_month,
    sum(rp.score) as score_in_month
  from recent_posts rp
  group by rp.owneruserid, date_trunc('month', rp.creationdate)
),
user_activity_ranks as (
  select
    uaw.*,
    row_number() over (partition by user_id order by month_bucket desc) as rn,
    sum(posts_in_month) over (partition by user_id order by month_bucket rows between 2 preceding and current row) as posts_last_3m,
    sum(score_in_month) over (partition by user_id order by month_bucket rows between 5 preceding and current row) as score_last_6m
  from user_activity_windows uaw
),
-- tag specialization: top tag per user using dense ranks
user_top_tags as (
  select user_id, tag, post_cnt, rank_in_user
  from (
    select
      rp.owneruserid as user_id,
      rp.tag,
      count(*) as post_cnt,
      dense_rank() over (partition by rp.owneruserid order by count(*) desc, lower(tag)) as rank_in_user
    from recent_posts rp
    where rp.tag is not null
    group by rp.owneruserid, rp.tag
  ) s
  where rank_in_user <= 3
),
-- unify all KPIs per user
user_all as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ru.lastaccessdate,
    ru.location,
    coalesce(ru.upvote_sum_window, 0) as upvote_sum_window,
    upk.q_count,
    upk.a_count,
    upk.total_post_score,
    upk.avg_views_nonzero,
    upk.max_post_score,
    upk.first_recent_post,
    upk.distinct_tags_used,
    uvk.net_votes,
    uvk.bounties_started,
    uvk.bounty_amount_total,
    uck.comment_count,
    uck.avg_comment_score,
    uck.positive_comments,
    uck.negative_comments,
    ubk.badge_count,
    ubk.distinct_badges,
    ubk.last_badge_date,
    ubk.gold_count,
    ubk.silver_count,
    ubk.bronze_count,
    ubk.tag_badges,
    uhk.closes,
    uhk.reopens,
    uhk.deletions_restores,
    uhk.suggested_edits_applied,
    uhk.hot_network,
    uhk.removed_hot,
    ulk.dup_marked_questions,
    ulk.linked_relations,
    max(case when uar.rn = 1 then uar.posts_in_month end) as posts_last_month,
    max(case when uar.rn = 1 then uar.score_in_month end) as score_last_month,
    max(uar.posts_last_3m) filter (where uar.rn = 1) as posts_last_3m,
    max(uar.score_last_6m) filter (where uar.rn = 1) as score_last_6m
  from recent_users ru
  left join user_post_kpis upk on upk.user_id = ru.user_id
  left join user_vote_kpis uvk on uvk.user_id = ru.user_id
  left join user_comment_kpis uck on uck.user_id = ru.user_id
  left join user_badge_kpis ubk on ubk.user_id = ru.user_id
  left join user_history_kpis uhk on uhk.user_id = ru.user_id
  left join user_link_kpis ulk on ulk.user_id = ru.user_id
  left join user_activity_ranks uar on uar.user_id = ru.user_id and uar.rn <= 6
  group by
    ru.user_id, ru.displayname, ru.reputation, ru.creationdate, ru.lastaccessdate, ru.location, ru.upvote_sum_window,
    upk.q_count, upk.a_count, upk.total_post_score, upk.avg_views_nonzero, upk.max_post_score, upk.first_recent_post, upk.distinct_tags_used,
    uvk.net_votes, uvk.bounties_started, uvk.bounty_amount_total,
    uck.comment_count, uck.avg_comment_score, uck.positive_comments, uck.negative_comments,
    ubk.badge_count, ubk.distinct_badges, ubk.last_badge_date, ubk.gold_count, ubk.silver_count, ubk.bronze_count, ubk.tag_badges,
    uhk.closes, uhk.reopens, uhk.deletions_restores, uhk.suggested_edits_applied, uhk.hot_network, uhk.removed_hot,
    ulk.dup_marked_questions, ulk.linked_relations
),
-- derive a composite score with various penalties/bonuses
scored as (
  select
    ua.*,
    coalesce(ua.total_post_score,0)
      + coalesce(ua.net_votes,0)*2
      + coalesce(ua.badge_count,0)*0.5
      + coalesce(ua.gold_count,0)*2
      + coalesce(ua.silver_count,0)*1
      + coalesce(ua.bronze_count,0)*0.5
      + coalesce(ua.score_last_6m,0)*1.5
      + coalesce(ua.posts_last_3m,0)*0.75
      + greatest(0, 10 - coalesce(ua.dup_marked_questions,0))*0.3
      - coalesce(ua.closes,0)*0.8
      - coalesce(ua.negative_comments,0)*0.4
      + coalesce(ua.positive_comments,0)*0.4
      + case when ua.avg_views_nonzero is null then 0 else ln(1 + ua.avg_views_nonzero) end
      + case when ua.distinct_tags_used >= 5 then 2 when ua.distinct_tags_used >= 2 then 1 else 0 end
      + case when ua.hot_network > 0 then 3 else 0 end
      - case when ua.removed_hot > 0 then 1 else 0 end
      + case when ua.reputation >= 10000 then 5 when ua.reputation >= 2000 then 2 else 0 end
      as composite_score
  from user_all ua
),
-- explode top tags for final presentation
top_tags_concat as (
  select
    utt.user_id,
    string_agg(utt.tag || ':' || utt.post_cnt::text, ', ' order by utt.post_cnt desc, utt.tag) as top_tags
  from user_top_tags utt
  group by utt.user_id
),
-- percentile ranks and bucketing
ranked as (
  select
    s.*,
    tt.top_tags,
    ntile(10) over (order by s.composite_score desc nulls last) as decile,
    percent_rank() over (order by s.composite_score) as pct_rank,
    row_number() over (order by s.composite_score desc nulls last, s.user_id) as global_rank
  from scored s
  left join top_tags_concat tt on tt.user_id = s.user_id
)
select
  r.global_rank,
  r.user_id,
  coalesce(nullif(trim(r.displayname), ''), '[user ' || r.user_id::text || ']') as display_name,
  r.location,
  r.reputation,
  r.q_count,
  r.a_count,
  r.total_post_score,
  r.net_votes,
  r.badge_count,
  r.gold_count,
  r.silver_count,
  r.bronze_count,
  r.posts_last_month,
  r.posts_last_3m,
  r.score_last_month,
  r.score_last_6m,
  r.dup_marked_questions,
  r.closes,
  r.positive_comments,
  r.negative_comments,
  coalesce(r.top_tags, 'none') as top_tags,
  round(r.composite_score::numeric, 2) as composite_score,
  r.decile,
  round(r.pct_rank::numeric, 4) as pct_rank,
  case
    when r.composite_score is null then 'inactive'
    when r.composite_score >= percentile_disc(0.9) within group (order by r.composite_score) then 'elite'
    when r.composite_score >= percentile_disc(0.7) within group (order by r.composite_score) then 'strong'
    when r.composite_score >= percentile_disc(0.4) within group (order by r.composite_score) then 'average'
    else 'novice'
  end as segment
from ranked r
where coalesce(r.q_count,0) + coalesce(r.a_count,0) > 0
order by r.global_rank
limit 200;