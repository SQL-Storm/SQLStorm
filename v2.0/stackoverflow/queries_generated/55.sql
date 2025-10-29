-- {"query": "55.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3236} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as website_norm,
           date_trunc('month', u.creationdate) as cohort_month,
           row_number() over (order by u.creationdate desc, u.id desc) as rn_global
    from users u
    where u.creationdate >= (select max(p.creationdate) - interval '365 days' from posts p)
),
user_activity as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        count(distinct p.id) as total_posts,
        sum(greatest(p.score,0)) as nonneg_score_sum,
        sum(case when p.viewcount is null then 0 else p.viewcount end) as total_views,
        max(p.lastactivitydate) as last_activity,
        count(*) filter (where p.closeddate is not null) as closed_posts,
        count(*) filter (where p.communityowneddate is not null) as community_posts
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
votes_agg as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 1) as accepted_by_originator,
        count(*) filter (where v.votetypeid = 9) as bounties_awarded,
        sum(coalesce(v.bountyamount,0)) as bounty_amount_sum
    from votes v
    group by v.postid
),
post_enriched as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.parentid,
        p.acceptedanswerid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.closeddate,
        p.title,
        p.tags,
        va.upvotes,
        va.downvotes,
        va.bounty_amount_sum,
        coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as net_votes,
        case
            when p.posttypeid = 1 then 'Question'
            when p.posttypeid = 2 then 'Answer'
            else 'Other'
        end as posttype_name
    from posts p
    left join votes_agg va on va.postid = p.id
),
question_answer_pairs as (
    select
        q.id as question_id,
        q.owneruserid as question_owner_id,
        q.creationdate as question_created,
        q.score as question_score,
        q.viewcount as question_views,
        q.tags as question_tags,
        q.title as question_title,
        a.id as answer_id,
        a.owneruserid as answer_owner_id,
        a.creationdate as answer_created,
        a.score as answer_score,
        a.viewcount as answer_views,
        case when q.acceptedanswerid = a.id then 1 else 0 end as is_accepted,
        a.net_votes as answer_net_votes
    from post_enriched q
    left join post_enriched a
      on a.parentid = q.id
     and a.posttypeid = 2
    where q.posttypeid = 1
),
answers_ranked as (
    select
        qap.*,
        row_number() over (partition by qap.question_id order by qap.is_accepted desc, qap.answer_score desc nulls last, qap.answer_created asc) as rn_best_answer,
        count(*) over (partition by qap.question_id) as answer_cnt
    from question_answer_pairs qap
),
tag_exploded as (
    select
        q.id as question_id,
        lower(trim(tg)) as tag_name
    from post_enriched q
    cross join lateral unnest(
        case
            when q.tags is null or length(q.tags) < 3 then array[]::varchar[]
            else string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')
        end
    ) as tg
    where q.posttypeid = 1
),
tag_rollup as (
    select
        te.tag_name,
        count(*) as questions_with_tag,
        count(distinct qap.answer_id) as total_answers_on_tagged_questions,
        avg(qap.answer_score::numeric) as avg_answer_score_on_tagged,
        sum(case when ar.rn_best_answer = 1 then 1 else 0 end) as questions_with_top_answer,
        sum(case when ar.is_accepted = 1 then 1 else 0 end) as accepted_answers_on_tagged
    from tag_exploded te
    join question_answer_pairs qap on qap.question_id = te.question_id
    join answers_ranked ar on ar.answer_id = qap.answer_id
    group by te.tag_name
),
link_dupes as (
    select
        pl.postid as question_id,
        count(*) filter (where pl.linktypeid = 3) as dup_links,
        count(*) filter (where pl.linktypeid = 1) as related_links
    from postlinks pl
    group by pl.postid
),
edits_stats as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_at,
        count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as mod_events
    from posthistory ph
    group by ph.postid
),
user_badges as (
    select
        b.userid,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges
    from badges b
    group by b.userid
),
activity_windows as (
    select
        p.owneruserid as user_id,
        date_trunc('month', p.creationdate) as month,
        count(*) as posts_in_month,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as questions_in_month,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as answers_in_month,
        avg(p.score::numeric) as avg_score_month
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid, date_trunc('month', p.creationdate)
),
activity_windows_ranked as (
    select
        aw.*,
        dense_rank() over (partition by aw.user_id order by aw.posts_in_month desc, aw.month desc) as dr_peak_month
    from activity_windows aw
),
user_quality as (
    select
        ua.user_id,
        ua.total_posts,
        ua.nonneg_score_sum,
        ua.total_views,
        coalesce(ub.badge_count,0) as badge_count,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        coalesce(ub.tag_badges,0) as tag_badges,
        coalesce(max(case when awr.dr_peak_month = 1 then awr.posts_in_month end),0) as peak_posts_in_month,
        coalesce(avg(awr.avg_score_month) filter (where awr.posts_in_month >= 1), 0)::numeric(12,4) as avg_monthly_post_score
    from user_activity ua
    left join user_badges ub on ub.userid = ua.user_id
    left join activity_windows_ranked awr on awr.user_id = ua.user_id
    group by ua.user_id, ua.total_posts, ua.nonneg_score_sum, ua.total_views, ub.badge_count, ub.gold_badges, ub.silver_badges, ub.bronze_badges, ub.tag_badges
),
question_scoped as (
    select
        q.id as question_id,
        q.owneruserid as owner_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.title,
        q.tags,
        coalesce(ld.dup_links,0) as dup_links,
        coalesce(ld.related_links,0) as related_links,
        coalesce(e.edits,0) as edit_count,
        e.first_edit_at,
        e.last_edit_at,
        q.net_votes,
        q.bounty_amount_sum
    from post_enriched q
    left join link_dupes ld on ld.question_id = q.id
    left join edits_stats e on e.postid = q.id
    where q.posttypeid = 1
),
answer_comp as (
    select
        ar.question_id,
        count(*) as answers_total,
        sum(case when ar.is_accepted = 1 then 1 else 0 end) as accepted_total,
        max(case when ar.rn_best_answer = 1 then ar.answer_score end) as top_answer_score,
        max(case when ar.rn_best_answer = 1 then ar.answer_owner_id end) as top_answer_owner,
        min(ar.answer_created) as first_answer_at,
        max(ar.answer_created) as last_answer_at
    from answers_ranked ar
    group by ar.question_id
),
owner_peer_compare as (
    select
        qs.question_id,
        qs.owner_id,
        uq.total_posts as owner_total_posts,
        uq.badge_count as owner_badges,
        uq.avg_monthly_post_score as owner_avg_monthly_score,
        percentile_disc(0.5) within group (order by uq.total_posts) over () as median_total_posts_global,
        percentile_disc(0.9) within group (order by uq.badge_count) over () as p90_badges_global
    from question_scoped qs
    left join user_quality uq on uq.user_id = qs.owner_id
),
recent_hot as (
    select
        qs.question_id,
        qs.owner_id,
        qs.creationdate,
        qs.score,
        qs.viewcount,
        qs.title,
        qs.tags,
        ac.answers_total,
        ac.accepted_total,
        ac.top_answer_score,
        ac.top_answer_owner,
        ac.first_answer_at,
        ac.last_answer_at,
        qs.dup_links,
        qs.related_links,
        qs.edit_count,
        qs.first_edit_at,
        qs.last_edit_at,
        qs.net_votes,
        qs.bounty_amount_sum,
        op.owner_total_posts,
        op.owner_badges,
        op.owner_avg_monthly_score,
        op.median_total_posts_global,
        op.p90_badges_global,
        coalesce(ac.answers_total,0) >= 1 as has_answers,
        case
            when qs.viewcount is null then 0
            when ac.answers_total is null or ac.answers_total = 0 then 0
            else (qs.viewcount::numeric / nullif(ac.answers_total,0))
        end as views_per_answer,
        extract(epoch from (coalesce(ac.first_answer_at, qs.creationdate) - qs.creationdate)) / 3600.0 as hours_to_first_answer
    from question_scoped qs
    left join answer_comp ac on ac.question_id = qs.question_id
    left join owner_peer_compare op on op.question_id = qs.question_id
    where qs.creationdate >= (select coalesce(max(p.creationdate), now()) - interval '90 days' from posts p)
),
ranked as (
    select
        rh.*,
        row_number() over (
            order by
                (coalesce(rh.viewcount,0) + 10*coalesce(rh.score,0) + 5*coalesce(rh.top_answer_score,0) + 3*coalesce(rh.related_links,0) - 2*coalesce(rh.dup_links,0) + coalesce(rh.bounty_amount_sum,0)) desc,
                rh.creationdate desc
        ) as rn_overall,
        dense_rank() over (order by coalesce(rh.tags,'') nulls last) as dr_tag_bucket,
        ntile(5) over (order by coalesce(rh.viewcount,0) desc) as nt_views_quintile
    from recent_hot rh
)
select
    r.question_id,
    r.title,
    coalesce(r.tags, '[untagged]') as tags,
    r.creationdate,
    r.score,
    r.viewcount,
    r.answers_total,
    r.accepted_total,
    r.top_answer_score,
    r.top_answer_owner,
    r.hours_to_first_answer,
    r.views_per_answer,
    r.dup_links,
    r.related_links,
    r.edit_count,
    r.net_votes,
    r.bounty_amount_sum,
    r.owner_id,
    r.owner_total_posts,
    r.owner_badges,
    r.owner_avg_monthly_score,
    r.median_total_posts_global,
    r.p90_badges_global,
    r.rn_overall,
    r.dr_tag_bucket,
    r.nt_views_quintile,
    -- correlated subquery examples and NULL logic
    (
        select count(1)
        from comments c
        where c.postid = r.question_id
          and (c.score > 0 or (c.text is not null and length(c.text) > 140))
    ) as comment_signal,
    (
        select count(distinct b.name)
        from badges b
        where b.userid = r.owner_id
          and b.tagbased = 1
    ) as distinct_tag_badges_owner,
    (
        select count(*)
        from postlinks pl
        where pl.relatedpostid = r.question_id
          and pl.linktypeid = 1
    ) as inbound_related_links
from ranked r
where (
        r.has_answers
        or (r.viewcount is not null and r.viewcount > 1000)
      )
  and coalesce(r.score,0) + coalesce(r.top_answer_score,0) >= 0
  and (
        r.tags is null
        or not exists (
            select 1
            from tag_rollup tr
            where tr.tag_name = any (
                case
                    when r.tags is null or length(r.tags) < 3 then array['']
                    else string_to_array(substring(r.tags, 2, length(r.tags)-2), '><')
                end
            )
            and tr.questions_with_tag < 3
        )
      )
order by r.rn_overall
limit 250;