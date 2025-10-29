-- {"query": "136.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3388} 
with recent_users as (
    select u.id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
           row_number() over (order by u.creationdate desc, u.id) as rn
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '6 months' from users)
),
top_recent_users as (
    select *
    from recent_users
    where rn <= 1000
),
user_badge_rollup as (
    select b.userid,
           count(*) as total_badges,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges,
           max(b.date) as last_badge_date
    from badges b
    join top_recent_users tru on tru.id = b.userid
    group by b.userid
),
user_posts as (
    select p.owneruserid as userid,
           count(*) filter (where p.posttypeid = 1) as q_count,
           count(*) filter (where p.posttypeid = 2) as a_count,
           sum(greatest(p.score, 0)) as nonneg_score_sum,
           sum(case when p.viewcount is not null and p.posttypeid = 1 then p.viewcount else 0 end) as q_views,
           max(p.lastactivitydate) as last_activity,
           count(*) filter (where p.closeddate is not null) as closed_posts
    from posts p
    join top_recent_users tru on tru.id = p.owneruserid
    group by p.owneruserid
),
accepted_answers as (
    select a.owneruserid as userid,
           count(*) as accepted_count
    from posts q
    join posts a on a.id = q.acceptedanswerid
    join top_recent_users tru on tru.id = a.owneruserid
    where q.posttypeid = 1 and a.posttypeid = 2
    group by a.owneruserid
),
vote_agg as (
    select v.userid,
           count(*) filter (where v.votetypeid = 2) as upvotes_cast,
           count(*) filter (where v.votetypeid = 3) as downvotes_cast,
           count(*) filter (where v.votetypeid = 8) as bounties_started,
           sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total_given
    from votes v
    join top_recent_users tru on tru.id = v.userid
    group by v.userid
),
comment_activity as (
    select c.userid,
           count(*) as comments_made,
           sum(greatest(c.score,0)) as comment_score_sum,
           max(c.creationdate) as last_comment_date
    from comments c
    join top_recent_users tru on tru.id = c.userid
    group by c.userid
),
tag_parse as (
    select p.id as postid,
           p.owneruserid as userid,
           unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
    from posts p
    where p.posttypeid = 1 and p.tags is not null
),
top_user_tags as (
    select tp.userid,
           tp.tagname,
           count(*) as tag_uses,
           row_number() over (partition by tp.userid order by count(*) desc, min(tp.postid)) as tag_rank
    from tag_parse tp
    group by tp.userid, tp.tagname
),
links_and_dupes as (
    select pl.postid,
           pl.relatedpostid,
           pl.linktypeid,
           count(*) over (partition by pl.postid, pl.linktypeid) as linktype_count_for_post,
           row_number() over (partition by pl.postid, pl.linktypeid order by pl.creationdate desc, pl.id desc) as link_rn
    from postlinks pl
),
question_quality as (
    select p.id as postid,
           p.owneruserid as userid,
           p.score,
           p.viewcount,
           p.answercount,
           coalesce(nullif(p.title,''), '(no title)') as norm_title,
           case
               when p.closeddate is not null then 0
               when p.score >= 5 and coalesce(p.viewcount,0) >= 500 then 3
               when p.score >= 2 and coalesce(p.viewcount,0) >= 200 then 2
               when p.score >= 0 then 1
               else 0
           end as quality_bucket,
           dense_rank() over (partition by p.owneruserid order by p.score desc, coalesce(p.viewcount,0) desc, p.id) as score_rank_within_user
    from posts p
    where p.posttypeid = 1
),
recent_posthistory as (
    select ph.postid,
           ph.posthistorytypeid,
           ph.userid,
           ph.creationdate,
           case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35) then ph.text else null end as meta_json
    from posthistory ph
    where ph.creationdate >= (select coalesce(max(creationdate) - interval '90 days', now() - interval '90 days') from posthistory)
),
close_reasons as (
    select ph.postid,
           max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_close_date
    from posthistory ph
    group by ph.postid
),
user_last_events as (
    select p.owneruserid as userid,
           max(p.lastactivitydate) as last_post_activity,
           max(q.last_close_date) as last_close_event
    from posts p
    left join close_reasons q on q.postid = p.id
    group by p.owneruserid
),
user_mixed as (
    select tru.id as userid,
           tru.displayname,
           tru.reputation,
           tru.creationdate,
           tru.location,
           tru.websiteurl,
           ub.total_badges,
           ub.gold_badges,
           ub.silver_badges,
           ub.bronze_badges,
           ub.tag_badges,
           ub.last_badge_date,
           up.q_count,
           up.a_count,
           up.nonneg_score_sum,
           up.q_views,
           up.last_activity as last_post_activity_candidate,
           up.closed_posts,
           aa.accepted_count,
           va.upvotes_cast,
           va.downvotes_cast,
           va.bounties_started,
           va.bounty_total_given,
           ca.comments_made,
           ca.comment_score_sum,
           ca.last_comment_date,
           ule.last_post_activity,
           ule.last_close_event
    from top_recent_users tru
    left join user_badge_rollup ub on ub.userid = tru.id
    left join user_posts up on up.userid = tru.id
    left join accepted_answers aa on aa.userid = tru.id
    left join vote_agg va on va.userid = tru.id
    left join comment_activity ca on ca.userid = tru.id
    left join user_last_events ule on ule.userid = tru.id
),
best_user_question as (
    select qq.userid,
           qq.postid as best_qid,
           qq.score as best_q_score,
           qq.viewcount as best_q_views,
           qq.answercount as best_q_answers
    from question_quality qq
    where qq.score_rank_within_user = 1
),
dupe_insights as (
    select p.owneruserid as userid,
           count(*) filter (where l.linktypeid = 3) as dupes_links_out,
           count(*) filter (where l.linktypeid = 1) as links_out,
           max(case when l.linktypeid = 3 and l.link_rn = 1 then l.relatedpostid end) as latest_dupe_target
    from posts p
    left join links_and_dupes l on l.postid = p.id
    where p.owneruserid in (select id from top_recent_users)
    group by p.owneruserid
),
windowed as (
    select um.*,
           coalesce(um.a_count,0) + coalesce(um.q_count,0) as total_posts,
           coalesce(um.upvotes_cast,0) - coalesce(um.downvotes_cast,0) as net_votes_cast,
           coalesce(um.accepted_count,0)::numeric / nullif(coalesce(um.a_count,0),0) as accept_rate,
           percent_rank() over (order by coalesce(um.reputation,0)) as rep_pr,
           dense_rank() over (order by coalesce(um.total_badges,0) desc nulls last, um.id) as badge_rank,
           row_number() over (order by coalesce(um.a_count,0) desc nulls last, coalesce(um.q_count,0) desc, um.id) as activity_rn
    from user_mixed um
),
blend as (
    select w.userid,
           w.displayname,
           w.reputation,
           w.creationdate,
           w.location,
           w.websiteurl,
           w.total_badges,
           w.gold_badges,
           w.silver_badges,
           w.bronze_badges,
           w.tag_badges,
           w.last_badge_date,
           w.q_count,
           w.a_count,
           w.nonneg_score_sum,
           w.q_views,
           w.closed_posts,
           w.accepted_count,
           w.upvotes_cast,
           w.downvotes_cast,
           w.bounties_started,
           w.bounty_total_given,
           w.comments_made,
           w.comment_score_sum,
           w.last_comment_date,
           w.last_post_activity,
           w.last_close_event,
           w.total_posts,
           w.net_votes_cast,
           w.accept_rate,
           w.rep_pr,
           w.badge_rank,
           w.activity_rn,
           buq.best_qid,
           buq.best_q_score,
           buq.best_q_views,
           buq.best_q_answers,
           dit.dupes_links_out,
           dit.links_out,
           dit.latest_dupe_target,
           tut.tagname as top_tag,
           tut.tag_uses
    from windowed w
    left join best_user_question buq on buq.userid = w.userid
    left join dupe_insights dit on dit.userid = w.userid
    left join top_user_tags tut on tut.userid = w.userid and tut.tag_rank = 1
),
ranked as (
    select b.*,
           -- composite score blending several metrics, with null-safety
           (
               0.35 * coalesce(log(greatest(b.reputation,1)), 0) +
               0.20 * coalesce(log(greatest(b.total_posts,1)), 0) +
               0.15 * coalesce(log(greatest(b.nonneg_score_sum + b.q_views/50.0,1)),0) +
               0.10 * coalesce(least(b.accept_rate, 1.0), 0) +
               0.08 * coalesce(log(greatest(b.total_badges,1)),0) +
               0.07 * coalesce(log(greatest(b.comments_made,1)),0) +
               0.05 * coalesce(case when b.closed_posts > 0 then 1.0/(b.closed_posts+1) else 1.0 end, 1.0)
           ) as composite_score,
           row_number() over (
               order by
                   (
                       0.35 * coalesce(log(greatest(b.reputation,1)), 0) +
                       0.20 * coalesce(log(greatest(b.total_posts,1)), 0) +
                       0.15 * coalesce(log(greatest(b.nonneg_score_sum + b.q_views/50.0,1)),0) +
                       0.10 * coalesce(least(b.accept_rate, 1.0), 0) +
                       0.08 * coalesce(log(greatest(b.total_badges,1)),0) +
                       0.07 * coalesce(log(greatest(b.comments_made,1)),0) +
                       0.05 * coalesce(case when b.closed_posts > 0 then 1.0/(b.closed_posts+1) else 1.0 end, 1.0)
                   ) desc,
                   b.userid
           ) as composite_rank
    from blend b
),
null_logic_probe as (
    select r.*,
           case when r.websiteurl ilike '%stackoverflow%' then 1 else 0 end as has_so_site,
           case when r.location is null or trim(r.location) = '' then 'unknown'
                when r.location ~* '(remote|earth|everywhere)' then 'generic'
                else 'specific' end as location_class,
           coalesce(nullif(regexp_replace(coalesce(r.displayname,''), '\s+', ' ', 'g'), ''), '(anonymous)') as normalized_displayname
    from ranked r
),
semi_anti as (
    select nl.userid
    from null_logic_probe nl
    where exists (
        select 1 from posts p
        where p.owneruserid = nl.userid and p.posttypeid = 1 and p.score >= 10
    )
    and not exists (
        select 1 from badges b
        where b.userid = nl.userid and b.class = 1
    )
),
final as (
    select nl.*,
           case when sa.userid is not null then 1 else 0 end as high_q_no_gold_badge,
           case
               when nl.dupes_links_out > 5 then 'likely_duplicateer'
               when nl.links_out > 20 then 'heavy_linker'
               when nl.accept_rate is not null and nl.accept_rate > 0.6 then 'helpful_answerer'
               else 'neutral'
           end as behavioral_label
    from null_logic_probe nl
    left join semi_anti sa on sa.userid = nl.userid
)
select
    f.userid,
    f.normalized_displayname as displayname,
    f.reputation,
    f.rep_pr,
    f.composite_score,
    f.composite_rank,
    f.total_posts,
    f.q_count,
    f.a_count,
    f.accepted_count,
    f.accept_rate,
    f.nonneg_score_sum,
    f.q_views,
    f.total_badges,
    f.gold_badges,
    f.silver_badges,
    f.bronze_badges,
    f.tag_badges,
    f.top_tag,
    f.tag_uses,
    f.best_qid,
    f.best_q_score,
    f.best_q_views,
    f.best_q_answers,
    f.dupes_links_out,
    f.links_out,
    f.latest_dupe_target,
    f.comments_made,
    f.comment_score_sum,
    f.last_post_activity,
    f.last_close_event,
    f.last_badge_date,
    f.has_so_site,
    f.location_class,
    f.behavioral_label
from final f
where
    (
        f.composite_rank <= 200
        or (f.accept_rate is not null and f.accept_rate >= 0.5 and f.a_count >= 5)
        or (f.q_count >= 5 and f.best_q_score >= 5)
    )
    and (f.location_class <> 'generic' or f.has_so_site = 1)
    and coalesce(f.displayname, '') not ilike '%bot%'
order by f.composite_rank nulls last, f.userid;