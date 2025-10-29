with recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.owneruserid,
    coalesce(p.ownerdisplayname, u.displayname) as owner_display,
    p.title,
    p.tags,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.closeddate,
    p.lastactivitydate
  from posts p
  left join users u on u.id = p.owneruserid
  where p.creationdate >= cast(cast('2024-10-01' as date) - interval '365' day as date)
),
user_activity as (
  select
    u.id as user_id,
    count(distinct p.id) filter (where p.posttypeid in (1,2)) as posts_authored,
    count(distinct c.id) as comments_authored,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes_cast,
    sum(case when b.class = 1 then 5 when b.class = 2 then 2 when b.class = 3 then 1 else 0 end) as badge_weight,
    max(u.reputation) as reputation,
    min(u.creationdate) as user_since
  from users u
  left join posts p on p.owneruserid = u.id and p.creationdate >= cast(cast('2024-10-01' as date) - interval '365' day as date)
  left join comments c on c.userid = u.id and c.creationdate >= cast(cast('2024-10-01' as date) - interval '365' day as date)
  left join votes v on v.userid = u.id and v.creationdate >= cast(cast('2024-10-01' as date) - interval '365' day as date)
  left join badges b on b.userid = u.id and b.date >= cast(cast('2024-10-01' as date) - interval '365' day as date)
  group by u.id
),
post_vote_stats as (
  select
    p.id as post_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    count(*) filter (where v.votetypeid in (10,12)) as deletions_or_spam
  from recent_posts p
  left join votes v on v.postid = p.id
  group by p.id
),
post_edit_stats as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edits,
    count(*) filter (where ph.posthistorytypeid in (10)) as closes,
    count(*) filter (where ph.posthistorytypeid in (11)) as reopens,
    max(ph.creationdate) as last_edit_date,
    sum(case when ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+$' then 1 else 0 end) as close_reason_events
  from posthistory ph
  join recent_posts rp on rp.id = ph.postid
  group by ph.postid
),
tag_explode as (
  select
    rp.id as post_id,
    lower(trim(both from t)) as tag
  from recent_posts rp,
  lateral unnest(string_to_array(substring(coalesce(rp.tags,''), 2, greatest(length(coalesce(rp.tags,'')) - 2, 0)), '><')) as t
),
tag_popularity as (
  select
    te.tag,
    count(*) as tag_uses,
    avg(rp.score) as avg_score_for_tag
  from tag_explode te
  join recent_posts rp on rp.id = te.post_id
  group by te.tag
),
dup_links as (
  select
    pl.postid as dup_post_id,
    pl.relatedpostid as original_post_id,
    pl.creationdate,
    pl.linktypeid
  from postlinks pl
  where pl.linktypeid = 3
),
accepted_answers as (
  select
    q.id as question_id,
    q.acceptedanswerid,
    a.owneruserid as answer_owner_id,
    a.score as accepted_answer_score
  from posts q
  left join posts a on a.id = q.acceptedanswerid
  where q.id in (select id from recent_posts where posttypeid = 1)
),
owner_quality as (
  select
    rp.owneruserid as user_id,
    count(*) as owner_posts,
    avg(coalesce(pvs.upvotes,0) - coalesce(pvs.downvotes,0)) as avg_net_votes,
    avg(rp.score) as avg_score,
    percentile_cont(0.9) within group (order by coalesce(pvs.upvotes,0) - coalesce(pvs.downvotes,0)) as p90_net_votes
  from recent_posts rp
  left join post_vote_stats pvs on pvs.post_id = rp.id
  where rp.owneruserid is not null
  group by rp.owneruserid
),
post_rank as (
  select
    rp.id,
    rp.posttypeid,
    rp.creationdate,
    rp.title,
    rp.owneruserid,
    coalesce(pvs.upvotes,0) as upvotes,
    coalesce(pvs.downvotes,0) as downvotes,
    coalesce(pvs.favorites,0) as favorites,
    coalesce(pvs.bounty_total,0) as bounty_total,
    coalesce(pes.edits,0) as edits,
    coalesce(pes.closes,0) as closes,
    coalesce(pes.reopens,0) as reopens,
    case when rp.viewcount is null or rp.viewcount = 0 then null
         else ( (coalesce(pvs.upvotes,0)::numeric) - (coalesce(pvs.downvotes,0)::numeric) / nullif(rp.viewcount,0) ) end as net_per_view,
    (coalesce(pvs.upvotes,0) * 2 + coalesce(pvs.favorites,0) + coalesce(pvs.bounty_total,0)/50 - coalesce(pvs.downvotes,0) - coalesce(pes.closes,0)*3) as engagement_score,
    row_number() over (partition by rp.posttypeid order by (coalesce(pvs.upvotes,0) - coalesce(pvs.downvotes,0)) desc, coalesce(pvs.favorites,0) desc) as rn_by_type,
    dense_rank() over (order by (coalesce(pvs.upvotes,0) - coalesce(pvs.downvotes,0)) desc) as global_rank
  from recent_posts rp
  left join post_vote_stats pvs on pvs.post_id = rp.id
  left join post_edit_stats pes on pes.postid = rp.id
),
question_quality as (
  select
    pr.id as question_id,
    pr.engagement_score,
    pr.net_per_view,
    aa.acceptedanswerid,
    aa.accepted_answer_score,
    case when aa.acceptedanswerid is not null then 1 else 0 end as has_accepted,
    sum(case when a.id is not null then 1 else 0 end) as total_answers_recent,
    avg(coalesce(a.score,0)) as avg_answer_score_recent
  from post_rank pr
  left join posts a on a.parentid = pr.id and a.creationdate >= pr.creationdate and a.posttypeid = 2
  left join accepted_answers aa on aa.question_id = pr.id
  where pr.posttypeid = 1
  group by pr.id, pr.engagement_score, pr.net_per_view, aa.acceptedanswerid, aa.accepted_answer_score
),
user_composite as (
  select
    ua.user_id,
    ua.posts_authored,
    ua.comments_authored,
    ua.net_votes_cast,
    ua.badge_weight,
    ua.reputation,
    ua.user_since,
    oq.owner_posts,
    oq.avg_net_votes,
    oq.avg_score,
    oq.p90_net_votes,
    (coalesce(ua.reputation,0)/100.0 + coalesce(oq.avg_net_votes,0) + coalesce(ua.badge_weight,0)) as composite_author_score
  from user_activity ua
  left join owner_quality oq on oq.user_id = ua.user_id
),
post_tag_agg as (
  select
    te.post_id,
    array_agg(te.tag order by tp.tag_uses desc, te.tag) as tags_sorted,
    sum(coalesce(tp.tag_uses,0)) as tag_popularity_sum
  from tag_explode te
  left join tag_popularity tp on tp.tag = te.tag
  group by te.post_id
),
closed_reason_extract as (
  select
    ph.postid,
    max(case when ph.posthistorytypeid = 10
             then cast(nullif(regexp_replace(coalesce(ph.comment,''),'[^0-9]','','g'), '') as integer)
             else null end) as last_close_reason_id
  from posthistory ph
  join recent_posts rp on rp.id = ph.postid
  group by ph.postid
),
engagement_percentiles as (
  select
    percentile_cont(0.9) within group (order by engagement_score) as p90,
    percentile_cont(0.75) within group (order by engagement_score) as p75,
    percentile_cont(0.5) within group (order by engagement_score) as p50
  from post_rank
),
final as (
  select
    pr.id as post_id,
    pr.posttypeid,
    pr.creationdate,
    pr.title,
    pr.owneruserid,
    coalesce(uc.composite_author_score, 0) as author_score,
    pr.upvotes,
    pr.downvotes,
    pr.favorites,
    pr.bounty_total,
    pr.edits,
    pr.closes,
    pr.reopens,
    pr.net_per_view,
    pr.engagement_score,
    pr.rn_by_type,
    pr.global_rank,
    case
      when pr.engagement_score >= ep.p90 then 'top10'
      when pr.engagement_score >= ep.p75 then 'top25'
      when pr.engagement_score >= ep.p50 then 'top50'
      else 'bottom50'
    end as qual_label,
    case
      when cr.last_close_reason_id is not null then cast(cr.last_close_reason_id as text)
      when pr.closes > 0 then 'unknown'
      else null
    end as close_reason_code,
    pta.tags_sorted,
    pta.tag_popularity_sum,
    coalesce(qq.total_answers_recent,0) as total_answers_recent,
    coalesce(qq.avg_answer_score_recent,0) as avg_answer_score_recent,
    qq.has_accepted,
    qq.accepted_answer_score
  from post_rank pr
  left join user_composite uc on uc.user_id = pr.owneruserid
  left join post_tag_agg pta on pta.post_id = pr.id
  left join closed_reason_extract cr on cr.postid = pr.id
  cross join engagement_percentiles ep
  left join question_quality qq on qq.question_id = pr.id
),
top_and_bottom as (
  select *
  from (
    select f.*, row_number() over (order by engagement_score desc nulls last, post_id) as rn_desc
    from final f
  ) t
  where rn_desc <= 200
  union all
  select *
  from (
    select f.*, row_number() over (order by engagement_score asc nulls last, post_id) as rn_asc
    from final f
  ) t2
  where rn_asc <= 200
),
with_dups as (
  select
    tab.*,
    dl.original_post_id,
    case when dl.original_post_id is not null then 'duplicate' else null end as dup_flag
  from top_and_bottom tab
  left join dup_links dl on dl.dup_post_id = tab.post_id
)
select
  w.post_id,
  w.posttypeid,
  w.creationdate,
  w.title,
  w.owneruserid,
  w.author_score,
  w.upvotes,
  w.downvotes,
  w.favorites,
  w.bounty_total,
  w.edits,
  w.closes,
  w.reopens,
  w.net_per_view,
  w.engagement_score,
  w.rn_by_type,
  w.global_rank,
  w.qual_label,
  w.close_reason_code,
  coalesce(array_to_string(w.tags_sorted, '|'), '') as tags_sorted,
  w.tag_popularity_sum,
  w.total_answers_recent,
  w.avg_answer_score_recent,
  w.has_accepted,
  w.accepted_answer_score,
  w.original_post_id,
  w.dup_flag,
  case
    when w.posttypeid = 1 and w.has_accepted = 1 and coalesce(w.accepted_answer_score,0) >= 5 then 'Resolved-HighScore'
    when w.posttypeid = 1 and w.closes > 0 then 'Closed'
    when w.posttypeid = 2 and w.upvotes - w.downvotes >= 10 then 'Answer-HighNet'
    when w.dup_flag = 'duplicate' then 'Duplicate'
    else 'Other'
  end as bucket
from with_dups w
where
  (
    w.engagement_score is not null
    and (w.upvotes - w.downvotes) between -50 and 500
    and coalesce(w.tag_popularity_sum, 0) >= 0
  )
  or (
    w.close_reason_code is not null
    and w.edits >= 0
  )
order by
  bucket,
  w.qual_label,
  w.engagement_score desc nulls last,
  w.post_id;