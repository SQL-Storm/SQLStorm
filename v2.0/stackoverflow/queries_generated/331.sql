-- {"query": "331.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3058} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
           row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) from users)
),
top_users as (
    select ru.*
    from recent_users ru
    where ru.rn <= 500
),
user_badge_agg as (
    select b.userid,
           count(*) as total_badges,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
user_posts as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as q_count,
           count(*) filter (where p.posttypeid = 2) as a_count,
           sum(coalesce(p.score,0)) as total_post_score,
           max(p.lastactivitydate) as last_post_activity,
           count(*) filter (where p.closeddate is not null) as closed_posts
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
accepted_answers as (
    select a.owneruserid as user_id,
           count(*) as accepted_count
    from posts q
    join posts a
      on a.id = q.acceptedanswerid
    where q.posttypeid = 1
      and a.posttypeid = 2
      and a.owneruserid is not null
    group by a.owneruserid
),
vote_agg as (
    select v.userid,
           count(*) filter (where v.votetypeid = 2) as upvotes_cast,
           count(*) filter (where v.votetypeid = 3) as downvotes_cast,
           count(*) filter (where v.votetypeid = 5) as favorites_cast,
           max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
    group by v.userid
),
comment_agg as (
    select c.userid,
           count(*) as comments_made,
           sum(coalesce(c.score,0)) as comment_score,
           avg(length(c.text))::numeric(10,2) as avg_comment_length,
           max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
tag_summary as (
    select p.owneruserid as user_id,
           count(*) as tagged_questions,
           -- approximate diversity: number of distinct first tag on questions
           count(distinct split_part(trim(both '<>' from coalesce(p.tags,'')), '><', 1)) as approx_tag_diversity
    from posts p
    where p.posttypeid = 1
      and p.owneruserid is not null
      and p.tags is not null
    group by p.owneruserid
),
dupe_links as (
    select pl.postid,
           count(*) filter (where pl.linktypeid = 3) as duplicate_links
    from postlinks pl
    group by pl.postid
),
post_history_flags as (
    select ph.postid,
           max(case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35) then 1 else 0 end) as has_moderation_events,
           count(*) filter (where ph.posthistorytypeid = 10) as close_events,
           count(*) filter (where ph.posthistorytypeid = 11) as reopen_events
    from posthistory ph
    group by ph.postid
),
user_quality as (
    select p.owneruserid as user_id,
           avg(case when p.posttypeid = 1 then nullif(p.viewcount,0) else null end) as avg_q_views,
           avg(case when p.posttypeid = 2 then nullif(p.score,0) else null end) as avg_a_score,
           percentile_cont(0.9) within group (order by coalesce(p.score,0)) as p90_post_score
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
recent_activity as (
    select u.id as user_id,
           greatest(
               coalesce(up.last_post_activity, timestamp 'epoch'),
               coalesce(va.last_vote_date, timestamp 'epoch'),
               coalesce(ca.last_comment_date, timestamp 'epoch'),
               coalesce(ub.last_badge_date, timestamp 'epoch')
           ) as most_recent_activity
    from users u
    left join user_posts up on up.user_id = u.id
    left join vote_agg va on va.userid = u.id
    left join comment_agg ca on ca.userid = u.id
    left join user_badge_agg ub on ub.userid = u.id
),
user_post_enrichment as (
    select p.owneruserid as user_id,
           sum(case when phf.has_moderation_events = 1 then 1 else 0 end) as posts_with_mod_events,
           sum(coalesce(dl.duplicate_links,0)) as total_duplicate_links
    from posts p
    left join post_history_flags phf on phf.postid = p.id
    left join dupe_links dl on dl.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
questions_last_year as (
    select p.owneruserid as user_id,
           count(*) as q_last_year,
           sum(coalesce(p.viewcount,0)) as q_views_last_year
    from posts p
    where p.posttypeid = 1
      and p.owneruserid is not null
      and p.creationdate >= (current_date - interval '365 days')
    group by p.owneruserid
),
ranked_users as (
    select tu.user_id,
           tu.displayname,
           tu.reputation,
           coalesce(upa.q_count,0) as q_count,
           coalesce(upa.a_count,0) as a_count,
           coalesce(aa.accepted_count,0) as accepted_count,
           coalesce(ua.total_badges,0) as total_badges,
           coalesce(ua.gold_badges,0) as gold_badges,
           coalesce(ua.silver_badges,0) as silver_badges,
           coalesce(ua.bronze_badges,0) as bronze_badges,
           coalesce(va.upvotes_cast,0) as upvotes_cast,
           coalesce(va.downvotes_cast,0) as downvotes_cast,
           coalesce(ca.comments_made,0) as comments_made,
           coalesce(ca.comment_score,0) as comment_score,
           coalesce(ts.tagged_questions,0) as tagged_questions,
           coalesce(ts.approx_tag_diversity,0) as approx_tag_diversity,
           coalesce(uq.avg_q_views,0) as avg_q_views,
           coalesce(uq.avg_a_score,0) as avg_a_score,
           coalesce(uq.p90_post_score,0) as p90_post_score,
           coalesce(ue.posts_with_mod_events,0) as posts_with_mod_events,
           coalesce(ue.total_duplicate_links,0) as total_duplicate_links,
           coalesce(qly.q_last_year,0) as q_last_year,
           coalesce(qly.q_views_last_year,0) as q_views_last_year,
           ra.most_recent_activity,
           tu.creationdate as user_created,
           tu.location,
           tu.websiteurl,
           -- score components
           (coalesce(upa.a_count,0) * 3
            + coalesce(aa.accepted_count,0) * 5
            + coalesce(upa.q_count,0) * 1
            + coalesce(uq.p90_post_score,0) * 0.5
            + coalesce(ua.gold_badges,0) * 8
            + coalesce(ua.silver_badges,0) * 3
            + coalesce(ua.bronze_badges,0) * 1
            + greatest(coalesce(va.upvotes_cast,0) - coalesce(va.downvotes_cast,0), 0) * 0.25
            + least(coalesce(ts.approx_tag_diversity,0), 50) * 0.2
            + coalesce(qly.q_views_last_year,0) / 100.0
           )::numeric(18,2) as activity_score,
           row_number() over (
               order by
                   (coalesce(upa.a_count,0) * 3
                    + coalesce(aa.accepted_count,0) * 5
                    + coalesce(upa.q_count,0) * 1
                    + coalesce(uq.p90_post_score,0) * 0.5
                    + coalesce(ua.gold_badges,0) * 8
                    + coalesce(ua.silver_badges,0) * 3
                    + coalesce(ua.bronze_badges,0) * 1
                    + greatest(coalesce(va.upvotes_cast,0) - coalesce(va.downvotes_cast,0), 0) * 0.25
                    + least(coalesce(ts.approx_tag_diversity,0), 50) * 0.2
                    + coalesce(qly.q_views_last_year,0) / 100.0
                   ) desc,
                   tu.reputation desc,
                   tu.user_id
           ) as rank_overall
    from top_users tu
    left join user_posts upa on upa.user_id = tu.user_id
    left join accepted_answers aa on aa.user_id = tu.user_id
    left join user_badge_agg ua on ua.userid = tu.user_id
    left join vote_agg va on va.userid = tu.user_id
    left join comment_agg ca on ca.userid = tu.user_id
    left join tag_summary ts on ts.user_id = tu.user_id
    left join user_quality uq on uq.user_id = tu.user_id
    left join user_post_enrichment ue on ue.user_id = tu.user_id
    left join questions_last_year qly on qly.user_id = tu.user_id
    left join recent_activity ra on ra.user_id = tu.user_id
),
dupe_vs_close as (
    select p.owneruserid as user_id,
           sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_links_out,
           sum(case when ph.posthistorytypeid = 10 and coalesce(nullif(ph.comment,''),'0')::int in (101) then 1 else 0 end) as closed_as_dup
    from posts p
    left join postlinks pl on pl.postid = p.id and pl.linktypeid = 3
    left join posthistory ph on ph.postid = p.id and ph.posthistorytypeid = 10
    where p.owneruserid is not null
    group by p.owneruserid
),
final_rank as (
    select r.*,
           coalesce(dvc.dup_links_out,0) as dup_links_out,
           coalesce(dvc.closed_as_dup,0) as closed_as_dup,
           case
               when coalesce(r.q_count,0) + coalesce(r.a_count,0) = 0 then null
               else (r.total_duplicate_links::numeric / nullif(coalesce(r.q_count,0) + coalesce(r.a_count,0),0))::numeric(18,4)
           end as dup_link_density,
           case
               when r.most_recent_activity is null or r.user_created is null then null
               else extract(epoch from (r.most_recent_activity - r.user_created)) / 86400.0
           end as lifetime_days
    from ranked_users r
    left join dupe_vs_close dvc on dvc.user_id = r.user_id
)
select
    fr.rank_overall,
    fr.user_id,
    fr.displayname,
    fr.reputation,
    fr.q_count,
    fr.a_count,
    fr.accepted_count,
    fr.total_badges,
    fr.gold_badges,
    fr.silver_badges,
    fr.bronze_badges,
    fr.upvotes_cast,
    fr.downvotes_cast,
    fr.comments_made,
    fr.comment_score,
    fr.tagged_questions,
    fr.approx_tag_diversity,
    fr.avg_q_views,
    fr.avg_a_score,
    fr.p90_post_score,
    fr.posts_with_mod_events,
    fr.total_duplicate_links,
    fr.dup_links_out,
    fr.closed_as_dup,
    fr.q_last_year,
    fr.q_views_last_year,
    fr.most_recent_activity,
    fr.user_created,
    fr.location,
    fr.websiteurl,
    fr.activity_score,
    coalesce(fr.dup_link_density, 0) as dup_link_density,
    coalesce(fr.lifetime_days, 0)::numeric(18,2) as lifetime_days,
    case
        when fr.activity_score >= percentile_disc(0.9) within group (order by fr.activity_score) over () then 'Elite'
        when fr.activity_score >= percentile_disc(0.75) within group (order by fr.activity_score) over () then 'High'
        when fr.activity_score >= percentile_disc(0.5) within group (order by fr.activity_score) over () then 'Medium'
        else 'Low'
    end as activity_bucket
from final_rank fr
where (
    -- complicated predicate combining null/empty, regex-like filter via position, and arithmetic
    (fr.location is null or position('Remote' in fr.location) > 0 or length(coalesce(fr.location,'')) >= 3)
    and (fr.websiteurl = 'N/A' or position('http' in fr.websiteurl) > 0)
    and coalesce(fr.avg_a_score,0) >= -5
)
order by fr.rank_overall
limit 200;