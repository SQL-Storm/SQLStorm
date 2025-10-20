with
user_posts as (
  select
    p.id as post_id,
    p.posttypeid,
    p.parentid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.owneruserid,
    p.tags,
    p.title,
    p.answercount,
    p.favoritecount
  from posts p
  where p.owneruserid is not null
),
question_tags as (
  select
    up.owneruserid as user_id,
    trim(tag) as tag
  from user_posts up,
  lateral (
    select regexp_split_to_table(substring(coalesce(up.tags,''), 2, greatest(length(coalesce(up.tags,'')) - 2,0)), '><') as tag
  ) t
  where up.posttypeid = 1 and coalesce(up.tags,'') <> ''
),
tag_counts as (
  select
    qt.user_id,
    qt.tag,
    count(*) as questions_with_tag
  from question_tags qt
  group by qt.user_id, qt.tag
),
badge_counts as (
  select
    b.userid,
    count(*) as total_badges,
    count(case when b.class = 1 then 1 end) as gold_badges,
    count(case when b.class = 2 then 1 end) as silver_badges,
    count(case when b.class = 3 then 1 end) as bronze_badges,
    bool_or(b.tagbased) as has_tag_badges
  from badges b
  group by b.userid
),
votes_on_posts as (
  select
    up.owneruserid as user_id,
    v.votetypeid,
    count(*) as cnt,
    sum(coalesce(v.bountyamount,0)) as total_bounty
  from posts up
  left join votes v on v.postid = up.id
  where up.owneruserid is not null
  group by up.owneruserid, v.votetypeid
),
votes_pivot as (
  select
    user_id,
    coalesce(max(case when votetypeid = 1 then cnt end),0) as accepted_count,
    coalesce(max(case when votetypeid = 2 then cnt end),0) as upvote_count,
    coalesce(max(case when votetypeid = 3 then cnt end),0) as downvote_count,
    coalesce(max(case when votetypeid = 8 then cnt end),0) as bounty_starts,
    coalesce(sum(total_bounty),0) as bounty_received
  from votes_on_posts
  group by user_id
),
posts_agg as (
  select
    up.owneruserid as user_id,
    count(case when up.posttypeid = 1 then 1 end) as questions,
    count(case when up.posttypeid = 2 then 1 end) as answers,
    sum(coalesce(up.score,0)) as total_score,
    max(up.creationdate) as last_post_date,
    min(up.creationdate) as first_post_date,
    avg(case when up.posttypeid = 1 then coalesce(up.viewcount,0) end) as avg_question_views,
    sum(case when up.posttypeid = 1 then coalesce(up.answercount,0) else 0 end) as total_answercount_on_questions,
    count(distinct up.post_id) as total_posts
  from user_posts up
  group by up.owneruserid
),
last_activity as (
  select
    u.id as user_id,
    greatest(
      coalesce((select max(p.creationdate) from posts p where p.owneruserid = u.id), timestamp '1970-01-01'),
      coalesce((select max(c.creationdate) from comments c where c.userid = u.id), timestamp '1970-01-01'),
      coalesce((select max(v.creationdate) from votes v where v.userid = u.id), timestamp '1970-01-01'),
      u.lastaccessdate
    ) as last_activity_date
  from users u
),
user_base as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    u.views as profile_views,
    u.upvotes as total_upvotes_given,
    u.downvotes as total_downvotes_given,
    coalesce(bc.total_badges,0) as total_badges,
    coalesce(bc.gold_badges,0) as gold_badges,
    coalesce(bc.silver_badges,0) as silver_badges,
    coalesce(bc.bronze_badges,0) as bronze_badges,
    coalesce(pagg.questions,0) as questions,
    coalesce(pagg.answers,0) as answers,
    coalesce(pagg.total_score,0) as total_score,
    coalesce(pagg.total_posts,0) as total_posts,
    coalesce(vp.accepted_count,0) as accepted_votes_on_posts,
    coalesce(vp.upvote_count,0) as upvotes_on_posts,
    coalesce(vp.downvote_count,0) as downvotes_on_posts,
    coalesce(vp.bounty_received,0) as bounty_received,
    la.last_activity_date,
    coalesce(pagg.last_post_date, u.creationdate) as last_post_date
  from users u
  left join badge_counts bc on bc.userid = u.id
  left join posts_agg pagg on pagg.user_id = u.id
  left join votes_pivot vp on vp.user_id = u.id
  left join last_activity la on la.user_id = u.id
),
scored_users as (
  select
    ub.id,
    ub.displayname,
    ub.reputation,
    ub.creationdate,
    ub.lastaccessdate,
    ub.profile_views,
    ub.total_upvotes_given,
    ub.total_downvotes_given,
    ub.total_badges,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges,
    ub.questions,
    ub.answers,
    ub.total_score,
    ub.total_posts,
    ub.accepted_votes_on_posts,
    ub.upvotes_on_posts,
    ub.downvotes_on_posts,
    ub.bounty_received,
    ub.last_activity_date,
    ub.last_post_date,
    exp(-least(365.0, extract(epoch from (timestamp '2024-10-01 12:34:56' - ub.last_activity_date))/86400.0) / 90.0) as recency_factor,
    (1 + ln(1 + cast(ub.gold_badges as numeric)) * 3 + ln(1 + cast(ub.silver_badges as numeric)) * 1.5 + ln(1 + cast(ub.bronze_badges as numeric)) * 0.75) as badge_factor,
    case when ub.total_posts > 0 then cast(ub.answers as numeric) / ub.total_posts else 0 end as answer_ratio,
    case when ub.total_posts > 0 then cast(ub.total_score as numeric) / ub.total_posts else 0 end as avg_score_per_post,
    (coalesce(ub.profile_views,0) + coalesce(ub.upvotes_on_posts,0) * 10 + coalesce(ub.accepted_votes_on_posts,0) * 25 + coalesce(ub.bounty_received,0)) as popularity_index,
    (
      (power(coalesce(ub.reputation,0), 0.35)) * 2.0
      + (coalesce(ub.total_score,0) / nullif(ub.total_posts,0) * 15.0)
      + (case when ub.total_posts > 0 then cast(ub.answers as numeric) / ub.total_posts else 0 end * 50.0)
      + (coalesce((coalesce(ub.profile_views,0) + coalesce(ub.upvotes_on_posts,0) * 10 + coalesce(ub.accepted_votes_on_posts,0) * 25 + coalesce(ub.bounty_received,0)),0) * 0.1)
    ) * (1 + (coalesce(ub.total_badges,0) / 50.0))
      * coalesce(exp(-nullif(extract(epoch from timestamp '2024-10-01 12:34:56' - ub.creationdate)/86400.0,0)/365.0),1)
      * coalesce(exp(-nullif(extract(epoch from timestamp '2024-10-01 12:34:56' - ub.last_activity_date)/86400.0,0)/180.0),1)
      * (1 + (case when ub.reputation > 10000 then 0.05 when ub.reputation > 1000 then 0.02 else 0 end))
    as raw_engagement_score
  from user_base ub
),
ranked as (
  select
    su.id,
    su.displayname,
    su.reputation,
    su.creationdate,
    su.lastaccessdate,
    su.profile_views,
    su.total_upvotes_given,
    su.total_downvotes_given,
    su.total_badges,
    su.gold_badges,
    su.silver_badges,
    su.bronze_badges,
    su.questions,
    su.answers,
    su.total_score,
    su.total_posts,
    su.accepted_votes_on_posts,
    su.upvotes_on_posts,
    su.downvotes_on_posts,
    su.bounty_received,
    su.last_activity_date,
    su.last_post_date,
    su.recency_factor,
    su.badge_factor,
    su.answer_ratio,
    su.avg_score_per_post,
    su.popularity_index,
    su.raw_engagement_score,
    row_number() over (order by su.raw_engagement_score desc) as engagement_rank,
    rank() over (order by su.raw_engagement_score desc) as engagement_dense_rank,
    ntile(100) over (order by su.raw_engagement_score desc) as percentile_rank,
    avg(su.raw_engagement_score) over (order by su.raw_engagement_score desc rows between 49 preceding and 49 following) as local_moving_avg_101,
    m.median_raw_score
  from scored_users su
  left join (
    select percentile_cont(0.5) within group (order by raw_engagement_score) as median_raw_score from scored_users
  ) m on true
),
top_tags as (
  select distinct on (tc.user_id)
    tc.user_id,
    tc.tag,
    tc.questions_with_tag
  from tag_counts tc
  order by tc.user_id, tc.questions_with_tag desc, tc.tag
),
final as (
  select
    r.engagement_rank,
    r.percentile_rank,
    r.id as user_id,
    coalesce(r.displayname, '<<unknown user>>') as display_name,
    r.reputation,
    r.total_posts,
    r.questions,
    r.answers,
    r.total_badges,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    round(r.raw_engagement_score,2) as engagement_score,
    round(r.local_moving_avg_101,2) as local_avg,
    r.recency_factor,
    r.badge_factor,
    r.answer_ratio,
    r.avg_score_per_post,
    r.popularity_index,
    coalesce(tt.tag, 'no-top-tag') as top_tag,
    tt.questions_with_tag,
    (
      select p.id from posts p
      where p.owneruserid = r.id
        and (p.posttypeid in (1,2))
        and (p.creationdate >= r.creationdate OR true)
      order by (coalesce(p.score,0) * 2 + coalesce(p.viewcount,0) / 100.0 + case when p.posttypeid = 1 then 5 else 0 end) desc,
               p.creationdate desc
      limit 1
    ) as exemplar_post_id,
    (
      coalesce(r.displayname,'Anonymous')
      || ' | R=' || coalesce(cast(r.reputation as text),'0')
      || ' | P=' || coalesce(cast(r.total_posts as text),'0')
      || ' | Q=' || coalesce(cast(r.questions as text),'0')
      || ' | A=' || coalesce(cast(r.answers as text),'0')
      || ' | B=' || coalesce(cast(r.total_badges as text),'0')
      || ' | T=' || coalesce(tt.tag,'-')
    ) as compact_summary
  from ranked r
  left join top_tags tt on tt.user_id = r.id
)
select * from (
  select * from final where total_posts >= 5 and engagement_rank <= 100
  union
  select * from final where user_id in (
    select id from users u where u.reputation >= 200000 limit 10
  )
) u
order by engagement_score desc, engagement_rank
limit 50;