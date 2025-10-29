with
params as (
  select
    cast(date_trunc('month', cast('2024-10-01 12:34:56' as timestamp)) - interval '24 months' as timestamp) as start_date,
    cast(cast('2024-10-01 12:34:56' as timestamp) as timestamp) as end_date,
    1 as posttype_question,
    2 as posttype_answer,
    2 as vote_up,
    3 as vote_down,
    5 as vote_favorite,
    3 as link_duplicate,
    10 as ph_closed,
    11 as ph_reopened
),
active_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
         case when u.websiteurl is null or u.websiteurl = '' then 0 else 1 end as has_website,
         count(*) over () as total_users_window
  from users u
),
recent_posts as (
  select p.id,
         p.posttypeid,
         p.creationdate,
         p.owneruserid,
         p.title,
         p.tags,
         p.score,
         p.viewcount,
         p.answercount,
         p.closeddate,
         p.communityowneddate
  from posts p
  cross join params pr
  where p.creationdate >= pr.start_date
    and p.creationdate < pr.end_date
    and p.posttypeid in (pr.posttype_question, pr.posttype_answer)
),
post_votes as (
  select v.postid,
         sum(case when v.votetypeid = pr.vote_up then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = pr.vote_down then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = pr.vote_favorite then 1 else 0 end) as favorites,
         count(*) as total_votes,
         max(v.creationdate) as last_vote_at
  from votes v
  cross join params pr
  join recent_posts rp on rp.id = v.postid
  group by v.postid
),
comment_stats as (
  select c.postid,
         count(*) as comment_count,
         sum(c.score) as comment_score_sum,
         avg(c.score) as comment_score_avg,
         max(c.creationdate) as last_comment_at
  from comments c
  join recent_posts rp on rp.id = c.postid
  group by c.postid
),
dup_links as (
  select pl.postid,
         sum(case when pl.linktypeid = pr.link_duplicate then 1 else 0 end) as duplicate_links_count,
         sum(case when pl.linktypeid <> pr.link_duplicate then 1 else 0 end) as other_links_count,
         bool_or(pl.linktypeid = pr.link_duplicate) as has_duplicate_link
  from postlinks pl
  cross join params pr
  join recent_posts rp on rp.id = pl.postid
  group by pl.postid
),
closure_events as (
  select ph.postid,
         min(case when ph.posthistorytypeid = pr.ph_closed then ph.creationdate end) as first_closed_at,
         max(case when ph.posthistorytypeid = pr.ph_closed then ph.creationdate end) as last_closed_at,
         sum(case when ph.posthistorytypeid = pr.ph_closed then 1 else 0 end) as closed_events,
         sum(case when ph.posthistorytypeid = pr.ph_reopened then 1 else 0 end) as reopened_events
  from posthistory ph
  cross join params pr
  join recent_posts rp on rp.id = ph.postid
  group by ph.postid
),
owner_rollup as (
  select
    rp.owneruserid as user_id,
    sum(case when rp.posttypeid = pr.posttype_question then 1 else 0 end) as q_count,
    sum(case when rp.posttypeid = pr.posttype_answer then 1 else 0 end) as a_count,
    sum(coalesce(pv.upvotes,0) - coalesce(pv.downvotes,0)) as net_votes,
    sum(coalesce(pv.favorites,0)) as favs,
    sum(coalesce(rp.viewcount,0)) as views_sum,
    max(coalesce(pv.last_vote_at, rp.creationdate)) as last_interaction_at
  from recent_posts rp
  cross join params pr
  left join post_votes pv on pv.postid = rp.id
  group by rp.owneruserid
),
tag_expansion as (
  select
    rp.id as post_id,
    unnest(string_to_array(substring(rp.tags, 2, greatest(length(rp.tags)-2,0)), '><')) as tagname
  from recent_posts rp
  where rp.posttypeid = (select posttype_question from params)
),
tag_stats as (
  select
    te.post_id,
    count(*) as tag_count,
    min(tagname) as first_tag_lex,
    max(tagname) as last_tag_lex
  from tag_expansion te
  group by te.post_id
),
ranked_posts as (
  select
    rp.id,
    rp.posttypeid,
    rp.creationdate,
    rp.owneruserid,
    rp.title,
    rp.score,
    rp.viewcount,
    row_number() over (partition by rp.owneruserid order by rp.creationdate desc, rp.id desc) as rn_recent_by_owner,
    rank() over (order by rp.score desc) as rnk_score_global,
    dense_rank() over (partition by rp.posttypeid order by rp.viewcount desc) as drnk_views_by_type
  from recent_posts rp
),
user_activity_bins as (
  select
    au.user_id,
    least(10, greatest(1, floor(
      extract(epoch from (coalesce(orup.last_interaction_at, au.creationdate) - au.creationdate))
      / (extract(epoch from interval '730 days') / 10.0)
    ))) as activity_bucket,
    count(*) over (partition by least(10, greatest(1, floor(
      extract(epoch from (coalesce(orup.last_interaction_at, au.creationdate) - au.creationdate))
      / (extract(epoch from interval '730 days') / 10.0)
    )))) as bucket_pop
  from active_users au
  left join owner_rollup orup on orup.user_id = au.user_id
),
predicate_build as (
  select
    rp.id as post_id,
    (coalesce(pv.upvotes,0) >= 5
     or (coalesce(pv.upvotes,0) - coalesce(pv.downvotes,0)) > 3
     or (rp.viewcount is not null and rp.viewcount > 1000 and rp.score >= 0)
     or (coalesce(closed.last_closed_at, rp.creationdate) > rp.creationdate + interval '90 days')
    ) as is_engaged,
    (case
      when rp.closeddate is not null or coalesce(dup.has_duplicate_link,false) then 'closed_or_dup'
      when coalesce(pv.downvotes,0) > coalesce(pv.upvotes,0) then 'controversial'
      when coalesce(pv.favorites,0) > 0 then 'favorited'
      else 'normal'
    end) as post_bucket
  from recent_posts rp
  left join post_votes pv on pv.postid = rp.id
  left join dup_links dup on dup.postid = rp.id
  left join closure_events closed on closed.postid = rp.id
),
first_top_answer as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid,
         a.score,
         a.creationdate,
         (
           select min(a2.creationdate)
           from posts a2
           where a2.posttypeid = (select posttype_answer from params)
             and a2.parentid = a.parentid
             and a2.score >= greatest(a.score, 1)
         ) as earliest_peer_time
  from posts a
  join params pr on true
  where a.posttypeid = pr.posttype_answer
    and a.creationdate >= (select start_date from params)
    and a.creationdate < (select end_date from params)
),
user_badge_agg as (
  select
    b.userid,
    count(*) as badge_count,
    sum(case when b.class = 1 then 1 else 0 end) as gold_count,
    sum(case when b.class = 2 then 1 else 0 end) as silver_count,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
    min(b.date) as first_badge_at,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
final_assemble as (
  select
    rp.id as post_id,
    rp.posttypeid,
    rp.creationdate,
    rp.owneruserid,
    coalesce(au.displayname, cast(rp.owneruserid as varchar) || ' (deleted?)') as owner_displayname_guess,
    rs.title,
    ts.tag_count,
    pv.upvotes,
    pv.downvotes,
    pv.favorites,
    pv.total_votes,
    cs.comment_count,
    cs.comment_score_avg,
    dl.duplicate_links_count,
    ce.closed_events,
    ce.reopened_events,
    rb.rn_recent_by_owner,
    rb.rnk_score_global,
    rb.drnk_views_by_type,
    pb.is_engaged,
    pb.post_bucket,
    oru.q_count,
    oru.a_count,
    oru.net_votes as owner_net_votes,
    uba.badge_count,
    uba.gold_count,
    uba.silver_count,
    uba.bronze_count,
    lag(rp.creationdate) over (partition by rp.owneruserid order by rp.creationdate) as prev_post_time_by_owner,
    lead(rp.creationdate) over (partition by rp.owneruserid order by rp.creationdate) as next_post_time_by_owner,
    (select count(*) from comments c where c.postid = rp.id and c.score > 0) as pos_comment_count_subq,
    case when rp.communityowneddate is not null then 1 else 0 end as is_community_owned,
    coalesce(ua.activity_bucket, 0) as user_activity_bucket,
    ua.bucket_pop as bucket_population
  from recent_posts rp
  left join users au on au.id = rp.owneruserid
  left join recent_posts rs on rs.id = rp.id
  left join post_votes pv on pv.postid = rp.id
  left join comment_stats cs on cs.postid = rp.id
  left join dup_links dl on dl.postid = rp.id
  left join closure_events ce on ce.postid = rp.id
  left join ranked_posts rb on rb.id = rp.id
  left join predicate_build pb on pb.post_id = rp.id
  left join owner_rollup oru on oru.user_id = rp.owneruserid
  left join tag_stats ts on ts.post_id = rp.id
  left join user_badge_agg uba on uba.userid = rp.owneruserid
  left join user_activity_bins ua on ua.user_id = rp.owneruserid
)
select *
from final_assemble fa
where (
        fa.posttypeid = (select posttype_question from params)
        and coalesce(fa.tag_count, 0) between 1 and 5
      )
   or (
        fa.posttypeid = (select posttype_answer from params)
        and (fa.upvotes - coalesce(fa.downvotes,0) >= 2
             or (fa.comment_count is not null and fa.comment_count > 3))
      )
order by
  fa.is_engaged desc,
  fa.post_bucket,
  fa.rnk_score_global,
  fa.drnk_views_by_type,
  fa.creationdate desc
limit 1000;