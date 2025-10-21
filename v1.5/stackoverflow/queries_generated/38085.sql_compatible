with recent_users as (
  select u.id as user_id, u.displayname, u.reputation, u.creationdate
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
q_posts as (
  select p.id, p.creationdate, p.score, p.viewcount, p.owneruserid, p.tags, p.title
  from posts p
  where p.posttypeid = 1
),
a_posts as (
  select p.id, p.parentid, p.creationdate, p.score, p.owneruserid
  from posts p
  where p.posttypeid = 2
),
tag_expanded as (
  select qp.id as question_id,
         unnest(string_to_array(substr(qp.tags, 2, length(qp.tags)-2), '><')) as tag
  from q_posts qp
  where qp.tags is not null and qp.tags like '<%>'
),
hot_questions as (
  select qp.id as question_id,
         qp.score,
         qp.viewcount,
         qp.creationdate,
         qp.owneruserid
  from q_posts qp
  where qp.score >= (select percentile_disc(0.9) within group (order by score) from q_posts where score is not null)
     or qp.viewcount >= (select percentile_disc(0.9) within group (order by viewcount) from q_posts where viewcount is not null)
),
answer_activity as (
  select ap.parentid as question_id,
         count(*) as answers_count,
         avg(ap.score) as avg_answer_score,
         max(ap.creationdate) as last_answer_date
  from a_posts ap
  group by ap.parentid
),
comment_activity as (
  select c.postid as post_id,
         count(*) filter (where c.score > 0) as pos_comments,
         count(*) filter (where c.score <= 0 or c.score is null) as nonpos_comments,
         max(c.creationdate) as last_comment_date
  from comments c
  group by c.postid
),
vote_rollup as (
  select v.postid as post_id,
         count(*) filter (where v.votetypeid = 2) as upvotes,
         count(*) filter (where v.votetypeid = 3) as downvotes,
         count(*) filter (where v.votetypeid = 5) as favorites,
         sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total
  from votes v
  group by v.postid
),
dup_links as (
  select pl.postid as dup_post_id,
         pl.relatedpostid as original_post_id,
         pl.creationdate as link_date
  from postlinks pl
  where pl.linktypeid = 3
),
close_events as (
  select ph.postid,
         sum(case when ph.posthistorytypeid = 10 then 1 else 0 end) as closes,
         sum(case when ph.posthistorytypeid = 11 then 1 else 0 end) as reopens,
         max(case when ph.posthistorytypeid in (10,11) then ph.creationdate else null end) as last_close_reopen
  from posthistory ph
  group by ph.postid
),
owner_stats as (
  select u.id as user_id,
         u.reputation,
         u.creationdate,
         coalesce(b.badge_gold,0) as badge_gold,
         coalesce(b.badge_silver,0) as badge_silver,
         coalesce(b.badge_bronze,0) as badge_bronze
  from users u
  left join (
    select userId,
           count(*) filter (where class = 1) as badge_gold,
           count(*) filter (where class = 2) as badge_silver,
           count(*) filter (where class = 3) as badge_bronze
    from badges
    group by userId
  ) b on b.userId = u.id
),
tag_popularity as (
  select te.tag,
         count(distinct te.question_id) as tag_questions,
         sum(hq.score) as tag_hot_score
  from tag_expanded te
  join hot_questions hq on hq.question_id = te.question_id
  group by te.tag
  having count(distinct te.question_id) >= 10
),
question_core as (
  select qp.id as question_id,
         qp.title,
         qp.creationdate,
         qp.score,
         qp.viewcount,
         qp.owneruserid,
         oa.answers_count,
         oa.avg_answer_score,
         oa.last_answer_date,
         coalesce(cr.closes,0) as closes,
         coalesce(cr.reopens,0) as reopens,
         cr.last_close_reopen,
         vr.upvotes,
         vr.downvotes,
         vr.favorites,
         vr.bounty_total,
         ca.pos_comments,
         ca.nonpos_comments,
         du.original_post_id as duplicate_of,
         du.link_date as duplicate_mark_date
  from q_posts qp
  left join answer_activity oa on oa.question_id = qp.id
  left join vote_rollup vr on vr.post_id = qp.id
  left join comment_activity ca on ca.post_id = qp.id
  left join close_events cr on cr.postid = qp.id
  left join dup_links du on du.dup_post_id = qp.id
),
owner_enriched as (
  select qc.*,
         os.reputation as owner_reputation,
         os.badge_gold,
         os.badge_silver,
         os.badge_bronze,
         ru.creationdate as owner_recent_creation
  from question_core qc
  left join owner_stats os on os.user_id = qc.owneruserid
  left join recent_users ru on ru.user_id = qc.owneruserid
),
tag_agg as (
  select te.question_id,
         array_agg(te.tag order by te.tag) as tags_array
  from tag_expanded te
  group by te.question_id
),
time_buckets as (
  select qc.question_id,
         date_trunc('month', qc.creationdate) as month_bucket
  from question_core qc
),
final_ranked as (
  select
    oe.question_id,
    oe.title,
    oe.creationdate,
    oe.score,
    oe.viewcount,
    oe.owneruserid,
    oe.owner_reputation,
    oe.badge_gold,
    oe.badge_silver,
    oe.badge_bronze,
    oe.answers_count,
    oe.avg_answer_score,
    oe.last_answer_date,
    oe.closes,
    oe.reopens,
    oe.last_close_reopen,
    oe.upvotes,
    oe.downvotes,
    oe.favorites,
    oe.bounty_total,
    oe.pos_comments,
    oe.nonpos_comments,
    oe.duplicate_of,
    oe.duplicate_mark_date,
    ta.tags_array,
    tb.month_bucket,
    sum(coalesce(oe.upvotes,0) - coalesce(oe.downvotes,0)) over (partition by tb.month_bucket) as net_votes_in_month,
    rank() over (partition by tb.month_bucket order by coalesce(oe.viewcount,0) desc, coalesce(oe.score,0) desc, coalesce(oe.answers_count,0) desc) as popularity_rank_in_month,
    dense_rank() over (order by coalesce(oe.score,0) desc) as global_score_rank
  from owner_enriched oe
  left join tag_agg ta on ta.question_id = oe.question_id
  left join time_buckets tb on tb.question_id = oe.question_id
)
select
  fr.*,
  tp.tag,
  tp.tag_questions,
  tp.tag_hot_score
from final_ranked fr
left join lateral (
  select t.tag, t.tag_questions, t.tag_hot_score
  from unnest(coalesce(fr.tags_array, ARRAY[])) as tag(tag)
  join tag_popularity t on t.tag = tag.tag
  order by t.tag_hot_score desc
  limit 3
) tp on true
where fr.popularity_rank_in_month <= 100
order by fr.month_bucket desc nulls last, fr.popularity_rank_in_month, fr.global_score_rank
limit 1000;