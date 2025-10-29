with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(lower(u.websiteurl)), ''), 'n/a') as norm_website
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
tagged_questions as (
    select p.id as question_id,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           string_to_array(substring(p.tags, 2, length(p.tags)-2), '><') as tag_array,
           p.answercount
    from posts p
    where p.posttypeid = 1
),
answers as (
    select a.id as answer_id,
           a.parentid as question_id,
           a.owneruserid,
           a.score as answer_score,
           a.creationdate as answer_date
    from posts a
    where a.posttypeid = 2
),
user_badge_rollup as (
    select b.userid,
           count(*) as total_badges,
           count(*) filter (where b.class = 1) as gold_badges,
           count(*) filter (where b.class = 2) as silver_badges,
           count(*) filter (where b.class = 3) as bronze_badges,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_activity as (
    select q.question_id,
           q.owneruserid as asker_id,
           q.creationdate as asked_at,
           q.score as question_score,
           q.viewcount,
           q.title,
           q.tag_array,
           coalesce(q.answercount, 0) as answercount_reported,
           count(a.answer_id) as answers_found,
           sum(case when a.answer_score > 0 then 1 else 0 end) as pos_answers,
           max(a.answer_score) as max_answer_score,
           min(a.answer_score) as min_answer_score,
           max(a.answer_date) as last_answer_date
    from tagged_questions q
    left join answers a on a.question_id = q.question_id
    group by q.question_id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.title, q.tag_array, q.answercount
),
first_last_comments as (
    select c.postid,
           min(c.creationdate) as first_comment_at,
           max(c.creationdate) as last_comment_at,
           count(*) as comment_count,
           sum(c.score) as comment_score_sum
    from comments c
    group by c.postid
),
dup_links as (
    select pl.postid as duplicate_id,
           pl.relatedpostid as canonical_id,
           count(*) as dup_links
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
vote_rollup as (
    select v.postid,
           count(*) filter (where v.votetypeid = 2) as upvotes,
           count(*) filter (where v.votetypeid = 3) as downvotes,
           count(*) filter (where v.votetypeid = 5) as favorites,
           count(*) filter (where v.votetypeid = 8) as bounties_started,
           sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total
    from votes v
    group by v.postid
),
post_last_edit as (
    select ph.postid,
           max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9)) as last_edit_at,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as closed_at,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as reopened_at,
           max(ph.creationdate) filter (where ph.posthistorytypeid in (12,10)) as mod_action_at,
           bool_or(ph.posthistorytypeid = 19) as ever_protected
    from posthistory ph
    group by ph.postid
),
user_activity as (
    select u.id as user_id,
           coalesce(sum(p.viewcount),0) as total_views_on_posts,
           coalesce(sum(p.score) filter (where p.posttypeid in (1,2)),0) as total_post_score,
           count(distinct p.id) filter (where p.posttypeid = 1) as questions_count,
           count(distinct p.id) filter (where p.posttypeid = 2) as answers_count,
           max(p.lastactivitydate) as last_post_activity
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
ranked_questions as (
    select qa.*,
           vr.upvotes,
           vr.downvotes,
           coalesce(vr.upvotes,0) - coalesce(vr.downvotes,0) as net_votes,
           flc.comment_count,
           flc.first_comment_at,
           flc.last_comment_at,
           ple.last_edit_at,
           ple.closed_at,
           ple.reopened_at,
           ple.ever_protected,
           dl.dup_links,
           row_number() over (partition by qa.asker_id order by qa.viewcount desc nulls last, qa.question_score desc nulls last) as rn_views,
           dense_rank() over (order by coalesce(vr.upvotes,0) - coalesce(vr.downvotes,0) desc, qa.viewcount desc) as global_popularity_rank
    from question_activity qa
    left join vote_rollup vr on vr.postid = qa.question_id
    left join first_last_comments flc on flc.postid = qa.question_id
    left join post_last_edit ple on ple.postid = qa.question_id
    left join dup_links dl on dl.duplicate_id = qa.question_id
),
user_quality as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.creationdate,
           ru.location,
           ru.norm_website,
           coalesce(ubr.total_badges,0) as total_badges,
           coalesce(ubr.gold_badges,0) as gold_badges,
           coalesce(ubr.silver_badges,0) as silver_badges,
           coalesce(ubr.bronze_badges,0) as bronze_badges,
           ua.total_views_on_posts,
           ua.total_post_score,
           ua.questions_count,
           ua.answers_count,
           ua.last_post_activity,
           case
             when coalesce(ua.answers_count,0) = 0 then null
             else round(CAST(ua.total_post_score AS numeric) / nullif(ua.answers_count,0), 2)
           end as avg_answer_score,
           case
             when coalesce(ua.questions_count,0) = 0 then null
             else round(CAST(ua.total_views_on_posts AS numeric) / nullif(ua.questions_count,0), 2)
           end as avg_question_views
    from recent_users ru
    left join user_badge_rollup ubr on ubr.userid = ru.user_id
    left join user_activity ua on ua.user_id = ru.user_id
),
top_question_per_user as (
    select rq.*
    from ranked_questions rq
    where rq.rn_views = 1
),
tag_explosion as (
    select tq.question_id,
           unnest(tq.tag_array) as tagname
    from tagged_questions tq
),
tag_rollup as (
    select te.tagname,
           count(*) as tagged_question_count,
           sum(case when rq.global_popularity_rank <= 100 then 1 else 0 end) as top100_count,
           avg(CAST(rq.viewcount AS numeric)) as avg_views_for_tag
    from tag_explosion te
    join ranked_questions rq on rq.question_id = te.question_id
    group by te.tagname
),
user_tag_affinity as (
    select tq.owneruserid as user_id,
           te.tagname,
           count(*) as q_count_for_tag,
           avg(CAST(tq.viewcount AS numeric)) as avg_views_for_tag_by_user
    from tagged_questions tq
    join tag_explosion te on te.question_id = tq.question_id
    group by tq.owneruserid, te.tagname
),
final_user_question as (
    select uq.user_id,
           uq.displayname,
           uq.reputation,
           uq.creationdate,
           uq.location,
           uq.norm_website,
           uq.total_badges,
           uq.gold_badges,
           uq.silver_badges,
           uq.bronze_badges,
           uq.total_views_on_posts,
           uq.total_post_score,
           uq.questions_count,
           uq.answers_count,
           uq.avg_answer_score,
           uq.avg_question_views,
           tq.question_id,
           rq.title,
           rq.viewcount,
           rq.question_score,
           rq.net_votes,
           rq.pos_answers,
           rq.max_answer_score,
           rq.min_answer_score,
           rq.last_answer_date,
           rq.comment_count,
           rq.first_comment_at,
           rq.last_comment_at,
           rq.last_edit_at,
           rq.closed_at,
           rq.reopened_at,
           rq.ever_protected,
           rq.dup_links,
           rq.global_popularity_rank
    from user_quality uq
    left join top_question_per_user rq on rq.asker_id = uq.user_id
    left join tagged_questions tq on tq.question_id = rq.question_id
)
select f.displayname,
       f.user_id,
       f.reputation,
       f.location,
       f.norm_website,
       f.total_badges,
       f.gold_badges,
       f.silver_badges,
       f.bronze_badges,
       f.questions_count,
       f.answers_count,
       f.avg_answer_score,
       f.avg_question_views,
       f.question_id as top_question_id,
       coalesce(f.title, '(no question)') as top_question_title,
       f.viewcount as top_question_views,
       f.question_score as top_question_score,
       f.net_votes as top_question_net_votes,
       f.pos_answers as positive_answers_on_top_q,
       f.max_answer_score as max_answer_score_on_top_q,
       f.comment_count as comment_count_on_top_q,
       f.last_edit_at as last_edit_on_top_q,
       f.closed_at as closed_at_on_top_q,
       f.global_popularity_rank,
       trim(both ' ' from coalesce(f.displayname, 'Anonymous') || ' | ' || coalesce(f.location, 'Somewhere')) as display_with_location,
       (
         select p2.id
         from dup_links dl2
         join posts p2 on p2.id = dl2.canonical_id
         where dl2.duplicate_id = f.question_id
         order by p2.score desc nulls last, p2.viewcount desc nulls last
         limit 1
       ) as canonical_target_id,
       (
         select string_agg(tn.tagname, ',' order by tn.tagname)
         from (
           select uta.tagname
           from user_tag_affinity uta
           where uta.user_id = f.user_id
           order by uta.q_count_for_tag desc nulls last, uta.avg_views_for_tag_by_user desc nulls last
           limit 5
         ) tn
       ) as top_user_tags,
       (
         select string_agg(tn.tagname || ':' || coalesce(CAST(tr.tagged_question_count AS text), '0'), ',' order by tn.tagname)
         from (
           select distinct on (te.tagname) te.tagname
           from tag_explosion te
           where te.question_id = f.question_id
           order by te.tagname
         ) tn
         left join tag_rollup tr on tr.tagname = tn.tagname
       ) as top_question_tag_stats
from final_user_question f
where (
        f.question_id is null
        or (
             f.viewcount >= coalesce(
               (select avg(viewcount) from posts p where p.posttypeid = 1 and p.creationdate >= f.creationdate),
               0
             )
             and coalesce(f.net_votes, 0) >= 0
           )
      )
and coalesce(f.gold_badges,0) + coalesce(f.silver_badges,0) + coalesce(f.bronze_badges,0) >= 0
and (
      f.norm_website like 'http%' or f.norm_website = 'n/a'
    )
order by
  case when f.question_id is null then 1 else 0 end,
  f.global_popularity_rank nulls last,
  f.reputation desc nulls last,
  f.total_badges desc nulls last,
  f.user_id
limit 500;