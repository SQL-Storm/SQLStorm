with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
active_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.parentid,
    p.lastactivitydate,
    p.commentcount,
    p.answercount
  from posts p
  where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
user_activity as (
  select
    ru.id as userid,
    count(distinct ap.id) filter (where ap.posttypeid in (1,2)) as posts_count,
    sum(ap.score) filter (where ap.posttypeid in (1,2)) as posts_score,
    count(distinct c.id) as comments_count,
    count(distinct v.id) as votes_cast,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes_cast
  from recent_users ru
  left join active_posts ap on ap.owneruserid = ru.id
  left join comments c on c.userid = ru.id and c.creationdate >= (select max(creationdate) - interval '365 days' from comments)
  left join votes v on v.userid = ru.id and v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
  group by ru.id, ru.displayname, ru.reputation, ru.creationdate, ru.location, ru.websiteurl_norm
),
post_engagement as (
  select
    ap.id as postid,
    ap.posttypeid,
    ap.owneruserid,
    coalesce(ap.score, 0) as score,
    coalesce(ap.viewcount, 0) as viewcount,
    coalesce(ap.commentcount, 0) as commentcount,
    coalesce(ap.answercount, 0) as answercount,
    sum(case when vt.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when vt.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when vt.votetypeid = 5 then 1 else 0 end) as favorites,
    max(case when ap.acceptedanswerid is not null then 1 else 0 end) as has_accepted,
    count(distinct pl.relatedpostid) filter (where pl.linktypeid = 3) as duplicate_of_count
  from active_posts ap
  left join votes vt on vt.postid = ap.id
  left join postlinks pl on pl.postid = ap.id
  group by ap.id, ap.posttypeid, ap.owneruserid, ap.score, ap.viewcount, ap.commentcount, ap.answercount, ap.acceptedanswerid
),
tag_explode as (
  select
    ap.id as postid,
    lower(trim(t::varchar)) as tag
  from active_posts ap,
  lateral unnest(string_to_array(substring(coalesce(ap.tags, '') from 2 for greatest(0, length(ap.tags)-2)), '><')) as t
  where ap.posttypeid = 1
),
user_top_tag as (
  select
    te_owner.owneruserid as userid,
    te_owner.tag,
    count(*) as tag_posts
  from (
    select ap.owneruserid, te.tag
    from active_posts ap
    join tag_explode te on te.postid = ap.id
    where ap.owneruserid is not null
  ) te_owner
  group by te_owner.owneruserid, te_owner.tag
),
user_top_tag_ranked as (
  select
    utt.userid,
    utt.tag,
    utt.tag_posts,
    row_number() over (partition by utt.userid order by utt.tag_posts desc, utt.tag asc) as rn
  from user_top_tag utt
),
user_badge_stats as (
  select
    u.id as userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when coalesce(b.tagbased, false) = true then 1 else 0 end) as tag_badges
  from users u
  left join badges b on b.userid = u.id and b.date >= (select max(date) - interval '365 days' from badges)
  group by u.id
),
question_answer_latency as (
  select
    q.id as questionid,
    min(a.creationdate) - q.creationdate as first_answer_latency
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
    and q.creationdate >= (select max(creationdate) - interval '365 days' from posts)
  group by q.id, q.creationdate
),
hotness as (
  select
    pe.postid,
    case
      when pe.viewcount = 0 then 0.0
      else (pe.upvotes - pe.downvotes) / nullif( ln(pe.viewcount + 1), 0 )
    end as hotness_score
  from post_engagement pe
),
user_rollups as (
  select
    ru.id as userid,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ru.location,
    ru.websiteurl_norm,
    ua.posts_count,
    ua.posts_score,
    ua.comments_count,
    ua.votes_cast,
    ua.net_votes_cast,
    ubs.total_badges,
    ubs.gold_badges,
    ubs.silver_badges,
    ubs.bronze_badges,
    ubs.tag_badges,
    coalesce(uttr.tag, '(none)') as top_tag,
    coalesce(uttr.tag_posts, 0) as top_tag_posts
  from recent_users ru
  left join user_activity ua on ua.userid = ru.id
  left join user_badge_stats ubs on ubs.userid = ru.id
  left join user_top_tag_ranked uttr on uttr.userid = ru.id and uttr.rn = 1
),
post_quality as (
  select
    pe.postid,
    pe.owneruserid,
    pe.posttypeid,
    pe.score,
    pe.viewcount,
    pe.commentcount,
    pe.answercount,
    pe.upvotes,
    pe.downvotes,
    pe.favorites,
    pe.has_accepted,
    pe.duplicate_of_count,
    coalesce(h.hotness_score, 0.0) as hotness_score,
    case
      when pe.posttypeid = 1 then
        (coalesce(pe.upvotes,0) * 3 + coalesce(pe.favorites,0) * 2 + coalesce(pe.commentcount,0) - coalesce(pe.downvotes,0) * 2 + case when pe.has_accepted = 1 then 5 else 0 end)
        - coalesce(pe.duplicate_of_count,0) * 4
      when pe.posttypeid = 2 then
        (coalesce(pe.upvotes,0) * 2 + coalesce(pe.commentcount,0) - coalesce(pe.downvotes,0) * 2)
      else
        coalesce(pe.upvotes,0) - coalesce(pe.downvotes,0)
    end as quality_score
  from post_engagement pe
  left join hotness h on h.postid = pe.postid
),
post_quality_ranked as (
  select
    pq.postid,
    pq.owneruserid,
    pq.posttypeid,
    pq.score,
    pq.viewcount,
    pq.commentcount,
    pq.answercount,
    pq.upvotes,
    pq.downvotes,
    pq.favorites,
    pq.has_accepted,
    pq.duplicate_of_count,
    pq.hotness_score,
    pq.quality_score,
    dense_rank() over (order by pq.quality_score desc, pq.hotness_score desc, pq.score desc) as global_rank,
    row_number() over (partition by pq.owneruserid order by pq.quality_score desc, pq.hotness_score desc, pq.score desc, pq.postid asc) as user_rank
  from post_quality pq
),
question_time_buckets as (
  select
    qal.questionid,
    case
      when qal.first_answer_latency is null then 'no-answer'
      when qal.first_answer_latency <= interval '1 hour' then '0-1h'
      when qal.first_answer_latency <= interval '6 hours' then '1-6h'
      when qal.first_answer_latency <= interval '24 hours' then '6-24h'
      when qal.first_answer_latency <= interval '3 days' then '1-3d'
      else '>3d'
    end as latency_bucket
  from question_answer_latency qal
),
user_quality_agg as (
  select
    pqr.owneruserid as userid,
    count(*) as total_active_posts,
    sum(case when pqr.posttypeid = 1 then 1 else 0 end) as questions_count,
    sum(case when pqr.posttypeid = 2 then 1 else 0 end) as answers_count,
    avg(pqr.quality_score) as avg_quality,
    percentile_cont(0.9) within group (order by pqr.quality_score) as p90_quality,
    sum(case when pqr.user_rank = 1 then 1 else 0 end) as top_posts_count,
    sum(case when pqr.global_rank <= 100 then 1 else 0 end) as top100_hits
  from post_quality_ranked pqr
  group by pqr.owneruserid
),
dup_clusters as (
  select
    ap.id as postid,
    count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as dup_targets,
    count(distinct case when pl2.linktypeid = 3 then pl2.postid end) as dup_sources
  from active_posts ap
  left join postlinks pl on pl.postid = ap.id
  left join postlinks pl2 on pl2.relatedpostid = ap.id
  group by ap.id
),
user_nullness as (
  select
    ru.id as userid,
    sum(case when ru.displayname is null or trim(ru.displayname) = '' then 1 else 0 end) as null_displayname,
    sum(case when ru.location is null or trim(ru.location) = '' then 1 else 0 end) as null_location,
    sum(case when ru.websiteurl_norm = 'n/a' then 1 else 0 end) as null_website
  from recent_users ru
  group by ru.id, ru.displayname, ru.reputation, ru.creationdate, ru.location, ru.websiteurl_norm
),
save_replacement as (
  select
    v.userid,
    count(*) as saves_like
  from votes v
  where v.votetypeid = 5
    and v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
  group by v.userid
),
final_users as (
  select
    ur.userid,
    ur.displayname,
    ur.reputation,
    ur.creationdate,
    ur.location,
    ur.websiteurl_norm,
    ua.posts_count,
    ua.posts_score,
    ua.comments_count,
    ua.votes_cast,
    ua.net_votes_cast,
    ur.total_badges,
    ur.gold_badges,
    ur.silver_badges,
    ur.bronze_badges,
    ur.tag_badges,
    ur.top_tag,
    ur.top_tag_posts,
    coalesce(uqa.total_active_posts, 0) as total_active_posts,
    coalesce(uqa.questions_count, 0) as questions_count,
    coalesce(uqa.answers_count, 0) as answers_count,
    coalesce(uqa.avg_quality, 0) as avg_quality,
    coalesce(uqa.p90_quality, 0) as p90_quality,
    coalesce(uqa.top_posts_count, 0) as top_posts_count,
    coalesce(uqa.top100_hits, 0) as top100_hits,
    coalesce(sn.saves_like, 0) as saves_like,
    un.null_displayname,
    un.null_location,
    un.null_website
  from user_rollups ur
  left join user_activity ua on ua.userid = ur.userid
  left join user_quality_agg uqa on uqa.userid = ur.userid
  left join save_replacement sn on sn.userid = ur.userid
  left join user_nullness un on un.userid = ur.userid
),
final_posts as (
  select
    pqr.postid,
    pqr.owneruserid,
    pqr.posttypeid,
    pqr.quality_score,
    pqr.hotness_score,
    pqr.global_rank,
    pqr.user_rank,
    dc.dup_targets,
    dc.dup_sources
  from post_quality_ranked pqr
  left join dup_clusters dc on dc.postid = pqr.postid
),
user_post_mix as (
  select
    fp.owneruserid as userid,
    sum(case when fp.posttypeid = 1 then 1 else 0 end) as q_count,
    sum(case when fp.posttypeid = 2 then 1 else 0 end) as a_count,
    avg(fp.quality_score) filter (where fp.posttypeid = 1) as avg_q_quality,
    avg(fp.quality_score) filter (where fp.posttypeid = 2) as avg_a_quality
  from final_posts fp
  group by fp.owneruserid
)
select
  fu.userid,
  coalesce(nullif(fu.displayname, ''), ('user#' || cast(fu.userid as varchar))) as displayname,
  fu.reputation,
  fu.creationdate,
  coalesce(nullif(fu.location, ''), '(unknown)') as location,
  fu.websiteurl_norm as websiteurl,
  fu.posts_count,
  fu.posts_score,
  fu.comments_count,
  fu.votes_cast,
  fu.net_votes_cast,
  fu.total_badges,
  fu.gold_badges,
  fu.silver_badges,
  fu.bronze_badges,
  fu.tag_badges,
  fu.top_tag,
  fu.top_tag_posts,
  fu.total_active_posts,
  fu.questions_count,
  fu.answers_count,
  round(cast(fu.avg_quality as numeric), 3) as avg_quality,
  round(cast(fu.p90_quality as numeric), 3) as p90_quality,
  fu.top_posts_count,
  fu.top100_hits,
  fu.saves_like,
  upm.q_count,
  upm.a_count,
  round(cast(coalesce(upm.avg_q_quality, 0) as numeric), 3) as avg_q_quality,
  round(cast(coalesce(upm.avg_a_quality, 0) as numeric), 3) as avg_a_quality,
  fu.null_displayname,
  fu.null_location,
  fu.null_website,
  (
    select string_agg(distinct lower(vt.name), ', ' order by lower(vt.name))
    from votes v2
    join votetypes vt on vt.id = v2.votetypeid
    where v2.userid = fu.userid
      and v2.creationdate >= (select max(creationdate) - interval '365 days' from votes)
  ) as vote_types_cast,
  (
    select string_agg(distinct lower(lt.name), ', ' order by lower(lt.name))
    from posts p2
    join postlinks pl on pl.postid = p2.id
    join linktypes lt on lt.id = pl.linktypeid
    where p2.owneruserid = fu.userid
      and p2.creationdate >= (select max(creationdate) - interval '365 days' from posts)
  ) as link_types_used,
  (
    select count(*)
    from final_posts fp2
    where fp2.owneruserid = fu.userid
      and fp2.global_rank <= 100
  ) as top100_posts_count,
  (
    select count(*)
    from final_posts fp3
    where fp3.owneruserid = fu.userid
      and fp3.dup_targets > 0
  ) as duplicate_flags_count
from final_users fu
left join user_post_mix upm on upm.userid = fu.userid
where
  coalesce(fu.reputation, 0) >= 0
  and (
    fu.posts_count is not null
    or fu.comments_count is not null
    or fu.votes_cast is not null
  )
order by
  fu.reputation desc nulls last,
  fu.userid asc
limit 500;