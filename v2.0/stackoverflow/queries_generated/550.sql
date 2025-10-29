-- {"query": "550.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3327} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_global
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as total_post_score,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as total_question_views,
        max(p.lastactivitydate) as last_activity,
        count(*) filter (where p.closeddate is not null) as closed_posts,
        count(*) filter (where p.communityowneddate is not null) as community_owned_posts
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
votes_by_user as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid in (8,9)) as bounties_interactions,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total
    from votes v
    where v.userid is not null
    group by v.userid
),
received_votes as (
    select
        p.owneruserid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_received,
        count(*) filter (where v.votetypeid = 3) as downvotes_received,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid = 9) as bounty_earned
    from posts p
    join votes v on v.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
comments_by_user as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        sum(coalesce(c.score,0)) as comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
badges_by_user as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_tag_explode as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        lower(t) as tagname
    from posts p
    cross join lateral unnest(
        coalesce(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><'), array[]::varchar[])
    ) as t
    where p.posttypeid = 1
),
top_tags_per_user as (
    select user_id, tagname, tag_cnt, rank() over (partition by user_id order by tag_cnt desc, tagname) as rnk
    from (
        select user_id, tagname, count(*) as tag_cnt
        from question_tag_explode
        group by user_id, tagname
    ) s
),
accepted_answerers as (
    select
        a.owneruserid as user_id,
        count(*) as accepted_answers
    from posts q
    join posts a on a.id = q.acceptedanswerid and a.posttypeid = 2
    where q.posttypeid = 1
    group by a.owneruserid
),
postlink_metrics as (
    select
        p.owneruserid as user_id,
        count(*) filter (where pl.linktypeid = 1) as links_linked,
        count(*) filter (where pl.linktypeid = 3) as links_duplicate
    from posts p
    join postlinks pl on pl.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
closed_reason_breakdown as (
    select
        ph.postid,
        try_cast(nullif(ph.comment, '') as int) as close_reason_id,
        count(*) as close_events
    from posthistory ph
    where ph.posthistorytypeid = 10
    group by ph.postid, try_cast(nullif(ph.comment, '') as int)
),
user_close_reasons as (
    select
        p.owneruserid as user_id,
        crt.name as close_reason_name,
        sum(crb.close_events) as close_events
    from posts p
    join closed_reason_breakdown crb on crb.postid = p.id
    left join closereasontypes crt on crt.id = crb.close_reason_id
    where p.owneruserid is not null
    group by p.owneruserid, crt.name
),
user_close_reason_pivot as (
    select
        user_id,
        sum(close_events) filter (where coalesce(close_reason_name,'Unknown') ilike '%duplicate%') as closed_duplicate,
        sum(close_events) filter (where coalesce(close_reason_name,'Unknown') ilike '%off%topic%') as closed_offtopic,
        sum(close_events) filter (where coalesce(close_reason_name,'Unknown') ilike '%needs%') as closed_needs_detail_or_focus,
        sum(close_events) filter (where coalesce(close_reason_name,'Unknown') ilike '%opinion%') as closed_opinion,
        sum(close_events) filter (where close_reason_name is null or close_reason_name = '') as closed_unknown
    from user_close_reasons
    group by user_id
),
user_recent_edits as (
    select
        ph.userid as user_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,24)) as edit_events,
        max(ph.creationdate) as last_edit_date
    from posthistory ph
    where ph.userid is not null
    group by ph.userid
),
activity_rankings as (
    select
        ru.user_id,
        dense_rank() over (order by coalesce(ua.q_count,0)+coalesce(ua.a_count,0) desc, coalesce(ua.total_post_score,0) desc) as rank_by_posts,
        dense_rank() over (order by coalesce(rv.upvotes_received,0)-coalesce(rv.downvotes_received,0) desc) as rank_by_net_received_votes,
        dense_rank() over (order by coalesce(vu.upvotes_cast,0)+coalesce(vu.downvotes_cast,0) desc) as rank_by_votes_cast,
        dense_rank() over (order by coalesce(bu.badge_count,0) desc, coalesce(bu.gold_badges,0) desc) as rank_by_badges
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join received_votes rv on rv.user_id = ru.user_id
    left join votes_by_user vu on vu.user_id = ru.user_id
    left join badges_by_user bu on bu.user_id = ru.user_id
),
cohort_engagement as (
    select
        ru.cohort_month,
        count(*) as users_in_cohort,
        avg(coalesce(ua.q_count,0)+coalesce(ua.a_count,0)) as avg_posts,
        percentile_cont(0.5) within group (order by coalesce(rv.upvotes_received,0)) as p50_upvotes_received
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join received_votes rv on rv.user_id = ru.user_id
    group by ru.cohort_month
),
qualified_users as (
    select
        ru.*,
        ua.*,
        vu.*,
        rv.*,
        cb.user_id as cb_user_id,
        bu.*,
        aa.accepted_answers,
        plm.links_linked, plm.links_duplicate,
        ucrp.closed_duplicate, ucrp.closed_offtopic, ucrp.closed_needs_detail_or_focus, ucrp.closed_opinion, ucrp.closed_unknown,
        ure.edit_events, ure.last_edit_date,
        ar.rank_by_posts, ar.rank_by_net_received_votes, ar.rank_by_votes_cast, ar.rank_by_badges
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join votes_by_user vu on vu.user_id = ru.user_id
    left join received_votes rv on rv.user_id = ru.user_id
    left join comments_by_user cb on cb.user_id = ru.user_id
    left join badges_by_user bu on bu.user_id = ru.user_id
    left join accepted_answerers aa on aa.user_id = ru.user_id
    left join postlink_metrics plm on plm.user_id = ru.user_id
    left join user_close_reason_pivot ucrp on ucrp.user_id = ru.user_id
    left join user_recent_edits ure on ure.user_id = ru.user_id
    left join activity_rankings ar on ar.user_id = ru.user_id
    where coalesce(ua.q_count,0) + coalesce(ua.a_count,0) + coalesce(cb.comment_count,0) > 0
),
top_tag_labels as (
    select
        tpu.user_id,
        string_agg(tagname || ':' || tag_cnt::text, ', ' order by tag_cnt desc, tagname) as top_tags_summary
    from top_tags_per_user tpu
    where rnk <= 3
    group by tpu.user_id
),
string_badge_summary as (
    select
        bu.user_id,
        ('G' || coalesce(bu.gold_badges,0)::text) || '/S' || coalesce(bu.silver_badges,0)::text || '/B' || coalesce(bu.bronze_badges,0)::text as badge_mix
    from badges_by_user bu
)
select
    qu.user_id,
    coalesce(qu.displayname, '(anonymous)') as displayname,
    qu.reputation,
    qu.location,
    qu.websiteurl,
    qu.cohort_month,
    coalesce(qu.q_count,0) as questions,
    coalesce(qu.a_count,0) as answers,
    coalesce(qu.accepted_answers,0) as accepted_answers,
    coalesce(qu.total_post_score,0) as total_post_score,
    coalesce(qu.total_question_views,0) as total_question_views,
    coalesce(qu.upvotes_received,0) - coalesce(qu.downvotes_received,0) as net_votes_received,
    coalesce(qu.upvotes_cast,0) - coalesce(qu.downvotes_cast,0) as net_votes_cast,
    coalesce(qu.bounty_earned,0) as bounty_earned,
    coalesce(qu.bounty_amount_total,0) as bounty_total_interactions,
    coalesce(qu.badge_count,0) as badges,
    coalesce(sbs.badge_mix,'G0/S0/B0') as badge_mix,
    coalesce(ttl.top_tags_summary, 'none') as top_tags,
    coalesce(qu.links_linked,0) as links_linked,
    coalesce(qu.links_duplicate,0) as links_duplicate,
    coalesce(qu.closed_duplicate,0) as closed_duplicate,
    coalesce(qu.closed_offtopic,0) as closed_offtopic,
    coalesce(qu.closed_needs_detail_or_focus,0) as closed_needs_detail_or_focus,
    coalesce(qu.closed_opinion,0) as closed_opinion,
    coalesce(qu.closed_unknown,0) as closed_unknown,
    coalesce(qu.edit_events,0) as edit_events,
    qu.last_activity,
    qu.last_edit_date,
    qu.rank_by_posts,
    qu.rank_by_net_received_votes,
    qu.rank_by_votes_cast,
    qu.rank_by_badges,
    case
        when coalesce(qu.q_count,0) = 0 and coalesce(qu.a_count,0) > 0 then 'Answerer'
        when coalesce(qu.q_count,0) > 0 and coalesce(qu.a_count,0) = 0 then 'Asker'
        when coalesce(qu.q_count,0) > 0 and coalesce(qu.a_count,0) > 0 then 'Hybrid'
        else 'Commenter'
    end as role_class,
    case when qu.reputation >= 20000 then 'Legend'
         when qu.reputation >= 10000 then 'Expert'
         when qu.reputation >= 2000 then 'Advanced'
         when qu.reputation >= 200 then 'Intermediate'
         else 'Beginner' end as rep_tier,
    -- correlated subqueries for additional per-user metrics
    coalesce((
        select avg(p.score)::numeric(12,2)
        from posts p
        where p.owneruserid = qu.user_id
          and p.posttypeid = 1
    ), 0) as avg_question_score,
    coalesce((
        select avg(p.score)::numeric(12,2)
        from posts p
        where p.owneruserid = qu.user_id
          and p.posttypeid = 2
    ), 0) as avg_answer_score,
    coalesce((
        select max(p.viewcount)
        from posts p
        where p.owneruserid = qu.user_id and p.posttypeid = 1
    ), 0) as max_question_views,
    coalesce((
        select count(distinct on (date_trunc('day', p.creationdate)) date_trunc('day', p.creationdate))
        from posts p
        where p.owneruserid = qu.user_id
    ), 0) as active_days_posted
from qualified_users qu
left join top_tag_labels ttl on ttl.user_id = qu.user_id
left join string_badge_summary sbs on sbs.user_id = qu.user_id
where
    (
        -- complex predicate mixing null logic and string ops
        (coalesce(qu.location,'') ilike any (array['%us%','%india%','%uk%','%de%'])
         or coalesce(qu.websiteurl,'') ~* '(github|gitlab|bitbucket)\.com'
        )
        or (coalesce(qu.total_post_score,0) >= 50 and coalesce(qu.badge_count,0) >= 5)
    )
    and (
        -- exclude users with only negative received votes unless they have an accepted answer
        not (coalesce(qu.upvotes_received,0) + coalesce(qu.downvotes_received,0) > 5 and coalesce(qu.upvotes_received,0) < coalesce(qu.downvotes_received,0))
        or coalesce(qu.accepted_answers,0) > 0
    )
order by
    qu.rank_by_posts,
    qu.rank_by_net_received_votes,
    qu.user_id
limit 500;