-- {"query": "264.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3963} 
with
-- recent active users with derived metrics
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(nullif(trim(u.location), ''), '(unknown)') as norm_location,
    u.upvotes,
    u.downvotes,
    (u.upvotes - u.downvotes) as net_votes,
    extract(epoch from (u.lastaccessdate - u.creationdate)) / 86400.0 as days_on_site
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
-- posts in the last 2 years with normalized tags array and post classification
recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.commentcount,
    p.favoritecount,
    p.title,
    p.tags,
    case when p.posttypeid = 1 then 1 else 0 end as is_question,
    case when p.posttypeid = 2 then 1 else 0 end as is_answer,
    string_to_array(substring(p.tags from 2 for greatest(length(p.tags)-2,0)), '><') as tag_arr
  from posts p
  where p.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from posts)
),
-- aggregate user activity over recent posts
user_post_aggs as (
  select
    rp.owneruserid as user_id,
    count(*) filter (where rp.is_question = 1) as q_count,
    count(*) filter (where rp.is_answer = 1) as a_count,
    sum(rp.score) as total_post_score,
    avg(rp.score)::numeric(18,4) as avg_post_score,
    sum(coalesce(rp.viewcount,0)) as total_views,
    sum(coalesce(rp.commentcount,0)) as total_comments,
    sum(coalesce(rp.favoritecount,0)) as total_favs,
    count(*) filter (where rp.score > 0) as pos_scored_posts,
    count(*) filter (where rp.score < 0) as neg_scored_posts
  from recent_posts rp
  where rp.owneruserid is not null
  group by rp.owneruserid
),
-- votes in last 2 years joined to recent posts to avoid scanning entire votes
votes_recent as (
  select v.*
  from votes v
  where v.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from votes)
),
-- vote aggregates by user via their posts
user_vote_aggs as (
  select
    rp.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_received,
    count(*) filter (where v.votetypeid = 3) as downvotes_received,
    count(*) filter (where v.votetypeid = 8) as bounties_started_on_posts,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total
  from recent_posts rp
  left join votes_recent v
    on v.postid = rp.id
  where rp.owneruserid is not null
  group by rp.owneruserid
),
-- comment activity for users on their own posts (last 2 years)
user_comment_aggs as (
  select
    rp.owneruserid as user_id,
    count(c.id) as comment_count_on_own_posts,
    avg(c.score)::numeric(18,4) as avg_comment_score_on_own_posts
  from recent_posts rp
  left join comments c
    on c.postid = rp.id
    and c.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from comments)
  where rp.owneruserid is not null
  group by rp.owneruserid
),
-- tag-level preferences: top tag per user by sum of post score and count
user_tag_scores as (
  select
    rp.owneruserid as user_id,
    lower(trim(t.tag)) as tag,
    count(*) as post_count,
    sum(rp.score) as tag_score
  from recent_posts rp
  cross join lateral unnest(coalesce(rp.tag_arr, array[]::varchar[])) as t(tag)
  where rp.owneruserid is not null
  group by rp.owneruserid, lower(trim(t.tag))
),
user_top_tag as (
  select distinct on (uts.user_id)
    uts.user_id,
    uts.tag as top_tag,
    uts.post_count as top_tag_posts,
    uts.tag_score as top_tag_score
  from user_tag_scores uts
  order by uts.user_id, uts.tag_score desc nulls last, uts.post_count desc, uts.tag asc
),
-- duplicates and links activity: counts of duplicates flagged and linked questions for user's questions
user_link_dupe as (
  select
    p.owneruserid as user_id,
    count(*) filter (where pl.linktypeid = 3 and p.posttypeid = 1) as duplicate_marks,
    count(*) filter (where pl.linktypeid = 1 and p.posttypeid = 1) as linked_marks
  from posts p
  left join postlinks pl
    on pl.postid = p.id
  where p.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from posts)
    and p.owneruserid is not null
  group by p.owneruserid
),
-- close reasons from PostHistory for user's questions
user_close_reasons as (
  select
    p.owneruserid as user_id,
    count(*) filter (where ph.posthistorytypeid = 10) as close_events,
    count(*) filter (
      where ph.posthistorytypeid = 10
        and nullif(ph.comment,'') ~ '^(101|102|103|104|105)$'
    ) as standardized_close_events
  from posts p
  join posthistory ph on ph.postid = p.id
  where p.posttypeid = 1
    and p.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from posts)
  group by p.owneruserid
),
-- activity pacing using window functions over time buckets
user_monthly_activity as (
  select
    rp.owneruserid as user_id,
    date_trunc('month', rp.creationdate) as month_bucket,
    count(*) as posts_in_month,
    sum(rp.score) as score_in_month
  from recent_posts rp
  where rp.owneruserid is not null
  group by rp.owneruserid, date_trunc('month', rp.creationdate)
),
user_activity_trends as (
  select
    uma.user_id,
    uma.month_bucket,
    posts_in_month,
    score_in_month,
    avg(posts_in_month) over (partition by uma.user_id order by month_bucket rows between 2 preceding and current row) as posts_3mo_ma,
    avg(score_in_month) over (partition by uma.user_id order by month_bucket rows between 2 preceding and current row) as score_3mo_ma,
    sum(posts_in_month) over (partition by uma.user_id order by month_bucket rows between unbounded preceding and current row) as cum_posts,
    sum(score_in_month) over (partition by uma.user_id order by month_bucket rows between unbounded preceding and current row) as cum_score,
    row_number() over (partition by uma.user_id order by month_bucket desc) as rn_desc
  from user_monthly_activity uma
),
-- latest trend snapshot per user
user_latest_trend as (
  select
    user_id,
    posts_in_month,
    score_in_month,
    posts_3mo_ma,
    score_3mo_ma,
    cum_posts,
    cum_score
  from user_activity_trends
  where rn_desc = 1
),
-- compute percentile ranks for reputation and total score for comparative benchmarking
benchmarks as (
  select
    ru.user_id,
    ru.reputation,
    upa.total_post_score,
    percent_rank() over (order by ru.reputation) as rep_prank,
    percent_rank() over (order by coalesce(upa.total_post_score,0)) as score_prank
  from recent_users ru
  left join user_post_aggs upa on upa.user_id = ru.user_id
),
-- enrich with badges (last 2 years), distinguishing class and tagbased
user_badge_aggs as (
  select
    b.userid as user_id,
    count(*) as badges_total,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where b.tagbased = 1) as tag_badges
  from badges b
  where b.date >= (select coalesce(max(date), now()) - interval '2 years' from badges)
  group by b.userid
),
-- identify "rising" users with correlated subquery on trend acceleration
rising_users as (
  select
    ru.user_id,
    exists (
      select 1
      from user_activity_trends t
      where t.user_id = ru.user_id
        and t.posts_3mo_ma is not null
        and t.score_3mo_ma is not null
        and t.score_in_month > coalesce(t.score_3mo_ma, 0)
        and t.posts_in_month >= coalesce(t.posts_3mo_ma, 0)
        and t.month_bucket >= (select max(month_bucket) - interval '6 months' from user_activity_trends where user_id = ru.user_id)
      limit 1
    ) as is_rising_recently
  from recent_users ru
),
-- tokenize domains for website url to test string expressions and null handling
user_domains as (
  select
    ru.user_id,
    case
      when ru.displayname ilike '%bot%' then '(bot)'
      else lower(
        regexp_replace(
          regexp_replace(coalesce(ru.displayname, ''), '\s+', '-', 'g'),
          '[^a-z0-9\-]', '', 'g'
        )
      )
    end as displayname_slug,
    case
      when ru.user_id is null then null
      else nullif(
        lower(
          regexp_replace(
            regexp_replace(coalesce(ru.user_id::text, ''), '\s+', '', 'g'),
            '[^a-z0-9]', '', 'g'
          )
        ), ''
      )
    end as user_id_slug,
    nullif(
      lower(
        regexp_replace(
          regexp_replace(coalesce(ru.norm_location, ''), '\s+', '-', 'g'),
          '[^a-z0-9\-]', '', 'g'
        )
      ), ''
    ) as location_slug
  from recent_users ru
),
-- combine all aggregates
combined as (
  select
    ru.user_id,
    ru.displayname,
    ru.norm_location,
    ru.reputation,
    ru.days_on_site,
    ru.net_votes,
    coalesce(upa.q_count,0) as q_count,
    coalesce(upa.a_count,0) as a_count,
    coalesce(upa.total_post_score,0) as total_post_score,
    upa.avg_post_score,
    coalesce(upa.total_views,0) as total_views,
    coalesce(upa.total_comments,0) as total_comments,
    coalesce(upa.total_favs,0) as total_favs,
    coalesce(uva.upvotes_received,0) as upvotes_received,
    coalesce(uva.downvotes_received,0) as downvotes_received,
    coalesce(uva.bounty_amount_total,0) as bounty_amount_total,
    coalesce(uca.comment_count_on_own_posts,0) as comments_on_own_posts,
    uca.avg_comment_score_on_own_posts,
    utl.posts_in_month as latest_posts_in_month,
    utl.score_in_month as latest_score_in_month,
    utl.posts_3mo_ma as posts_3mo_ma,
    utl.score_3mo_ma as score_3mo_ma,
    utl.cum_posts as cum_posts_recent,
    utl.cum_score as cum_score_recent,
    coalesce(ut.tag_score,0) as top_tag_score,
    ut.top_tag,
    ut.top_tag_posts,
    coalesce(uld.duplicate_marks,0) as duplicate_marks,
    coalesce(uld.linked_marks,0) as linked_marks,
    coalesce(ucr.close_events,0) as close_events,
    coalesce(ucr.standardized_close_events,0) as standardized_close_events,
    coalesce(uba.badges_total,0) as badges_total,
    coalesce(uba.gold_badges,0) as gold_badges,
    coalesce(uba.silver_badges,0) as silver_badges,
    coalesce(uba.bronze_badges,0) as bronze_badges,
    coalesce(uba.tag_badges,0) as tag_badges,
    b.rep_prank,
    b.score_prank,
    ru.lastaccessdate,
    case
      when coalesce(upa.q_count,0) + coalesce(upa.a_count,0) = 0 then null
      else (coalesce(upa.total_post_score,0)::numeric / nullif(coalesce(upa.q_count,0) + coalesce(upa.a_count,0),0))::numeric(18,4)
    end as score_per_post,
    case
      when ru.days_on_site <= 0 then null
      else (coalesce(upa.q_count,0) + coalesce(upa.a_count,0)) / ru.days_on_site
    end as posts_per_day_recent,
    case when ru.reputation >= 10000 then 'high'
         when ru.reputation >= 3000 then 'mid'
         else 'low' end as rep_bucket
  from recent_users ru
  left join user_post_aggs upa on upa.user_id = ru.user_id
  left join user_vote_aggs uva on uva.user_id = ru.user_id
  left join user_comment_aggs uca on uca.user_id = ru.user_id
  left join user_latest_trend utl on utl.user_id = ru.user_id
  left join user_top_tag ut on ut.user_id = ru.user_id
  left join user_link_dupe uld on uld.user_id = ru.user_id
  left join user_close_reasons ucr on ucr.user_id = ru.user_id
  left join user_badge_aggs uba on uba.user_id = ru.user_id
  left join benchmarks b on b.user_id = ru.user_id
),
-- outlier filtering and ranking using window functions and complex predicates
ranked as (
  select
    c.*,
    row_number() over (order by c.total_post_score desc nulls last, c.upvotes_received desc, c.reputation desc) as rn_score,
    row_number() over (order by c.posts_per_day_recent desc nulls last, c.cum_posts_recent desc, c.reputation desc) as rn_activity,
    row_number() over (order by c.badges_total desc nulls last, c.gold_badges desc, c.silver_badges desc, c.bronze_badges desc) as rn_badges,
    dense_rank() over (partition by c.rep_bucket order by c.total_post_score desc nulls last) as dr_by_rep_bucket,
    case
      when (c.top_tag is null or c.top_tag = '') and c.q_count > 0 then 'untagged'
      when c.top_tag is null then 'none'
      else c.top_tag
    end as normalized_top_tag
  from combined c
  where
    -- exclude likely bots by name and zero-activity edge cases
    not (c.displayname ilike '%bot%' and c.q_count = 0 and c.a_count = 0)
    and (c.q_count + c.a_count) >= 1
)
select
  r.user_id,
  r.displayname,
  r.norm_location,
  r.reputation,
  r.rep_bucket,
  r.upvotes_received,
  r.downvotes_received,
  r.q_count,
  r.a_count,
  r.total_post_score,
  r.avg_post_score,
  r.score_per_post,
  r.total_views,
  r.total_comments,
  r.total_favs,
  r.latest_posts_in_month,
  r.latest_score_in_month,
  r.posts_3mo_ma,
  r.score_3mo_ma,
  r.cum_posts_recent,
  r.cum_score_recent,
  r.normalized_top_tag as top_tag,
  r.top_tag_posts,
  r.top_tag_score,
  r.duplicate_marks,
  r.linked_marks,
  r.close_events,
  r.standardized_close_events,
  r.badges_total,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.tag_badges,
  r.rep_prank,
  r.score_prank,
  r.rn_score,
  r.rn_activity,
  r.rn_badges,
  r.dr_by_rep_bucket,
  case when coalesce(r.upvotes_received,0) + coalesce(r.downvotes_received,0) = 0 then null
       else r.upvotes_received::numeric / nullif((r.upvotes_received + r.downvotes_received),0) end as upvote_ratio_received,
  case when r.total_views is null or r.total_views = 0 then null
       else r.total_post_score::numeric / nullif(r.total_views,0) end as score_per_view,
  case when r.total_comments is null or r.total_comments = 0 then null
       else r.total_post_score::numeric / nullif(r.total_comments,0) end as score_per_comment,
  case when r.total_favs is null or r.total_favs = 0 then null
       else r.total_post_score::numeric / nullif(r.total_favs,0) end as score_per_fav,
  case
    when r.is_rising_recently then 'rising'
    when r.score_prank >= 0.9 then 'top-scorer'
    when r.rep_prank >= 0.9 then 'top-rep'
    else 'steady'
  end as momentum_label
from ranked r
left join rising_users ru on ru.user_id = r.user_id
order by
  r.rn_score,
  r.rn_activity,
  r.rn_badges
limit 500;