-- {"query": "596.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3386} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        u.upvotes,
        u.downvotes,
        u.views,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        coalesce(sum(p.score), 0) as total_post_score,
        count(*) filter (where p.closeddate is not null) as closed_posts,
        avg(p.viewcount) filter (where p.viewcount is not null) as avg_views_per_post,
        count(distinct p.id) as total_posts,
        max(p.lastactivitydate) as last_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
answer_accepts as (
    select
        a.owneruserid as user_id,
        count(*) as accepted_answers
    from posts q
    join posts a on a.parentid = q.id and a.posttypeid = 2 and q.posttypeid = 1
    where q.acceptedanswerid = a.id
    group by a.owneruserid
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as comments_count,
        sum(case when c.score >= 5 then 1 else 0 end) as high_scored_comments,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
badge_stats as (
    select
        b.userid as user_id,
        count(*) as total_badges,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
tag_extract as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
    from posts p
    where p.posttypeid = 1 and p.tags is not null and length(p.tags) > 2
),
user_top_tags as (
    select
        te.user_id,
        array_agg(t.tagname order by t.count desc) filter (where t.tagname is not null) as top_tags_by_popularity,
        array_agg(distinct te.tag) as user_tag_set,
        count(distinct te.tag) as distinct_tags_used
    from tag_extract te
    left join tags t on t.tagname = te.tag
    group by te.user_id
),
dup_links as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.linktypeid,
        pl.creationdate,
        case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate_link
    from postlinks pl
),
post_history_flags as (
    select
        ph.postid,
        max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as was_closed_or_migrated,
        count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as mod_actions_count,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as last_mod_action_date,
        count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied
    from posthistory ph
    group by ph.postid
),
vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount, 0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount, 0) else 0 end) as bounty_awarded,
        count(*) filter (where v.votetypeid in (10,11,12)) as del_undel_spam_votes
    from votes v
    group by v.postid
),
question_metrics as (
    select
        q.owneruserid as user_id,
        count(*) as questions_count,
        avg(q.score) as avg_q_score,
        sum(case when q.acceptedanswerid is not null then 1 else 0 end) as questions_with_accepted,
        sum(q.viewcount) filter (where q.viewcount is not null) as total_q_views,
        sum(va.upvotes) as q_upvotes,
        sum(va.downvotes) as q_downvotes,
        sum(phf.mod_actions_count) as q_mod_actions,
        sum(dl.is_duplicate_link) as q_duplicate_links
    from posts q
    left join vote_agg va on va.postid = q.id
    left join post_history_flags phf on phf.postid = q.id
    left join dup_links dl on dl.postid = q.id and dl.linktypeid in (1,3)
    where q.posttypeid = 1
    group by q.owneruserid
),
answer_metrics as (
    select
        a.owneruserid as user_id,
        count(*) as answers_count,
        avg(a.score) as avg_a_score,
        sum(va.upvotes) as a_upvotes,
        sum(va.downvotes) as a_downvotes,
        sum(phf.mod_actions_count) as a_mod_actions
    from posts a
    left join vote_agg va on va.postid = a.id
    left join post_history_flags phf on phf.postid = a.id
    where a.posttypeid = 2
    group by a.owneruserid
),
activity_window as (
    select
        p.owneruserid as user_id,
        p.id as post_id,
        p.creationdate,
        p.score,
        row_number() over (partition by p.owneruserid order by p.creationdate desc) as rn_recent,
        sum(p.score) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as cumulative_score,
        avg(p.score) over (partition by p.owneruserid order by p.creationdate rows between 10 preceding and current row) as moving_avg_score_11
    from posts p
    where p.owneruserid is not null
),
recent_activity as (
    select
        user_id,
        max(case when rn_recent = 1 then post_id end) as most_recent_post_id,
        max(case when rn_recent = 1 then creationdate end) as most_recent_post_date,
        max(case when rn_recent = 1 then score end) as most_recent_post_score,
        max(cumulative_score) as cumulative_score_latest,
        max(moving_avg_score_11) as moving_avg_score_11_latest
    from activity_window
    group by user_id
),
engagement_score as (
    select
        ru.user_id,
        (
            coalesce(ua.total_posts, 0) * 0.2
            + coalesce(am.answers_count, 0) * 0.5
            + coalesce(qm.questions_count, 0) * 0.4
            + greatest(coalesce(cs.comments_count, 0) - coalesce(cs.high_scored_comments, 0), 0) * 0.05
            + coalesce(qm.q_upvotes, 0) * 0.1
            - coalesce(qm.q_downvotes, 0) * 0.08
            + coalesce(am.a_upvotes, 0) * 0.12
            - coalesce(am.a_downvotes, 0) * 0.1
            + least(coalesce(b.badge_stats_weight, 0), 200)
        ) as engagement_score_raw
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join question_metrics qm on qm.user_id = ru.user_id
    left join answer_metrics am on am.user_id = ru.user_id
    left join comment_stats cs on cs.user_id = ru.user_id
    left join (
        select
            bs.user_id,
            (coalesce(bs.gold_badges,0) * 10 + coalesce(bs.silver_badges,0) * 4 + coalesce(bs.bronze_badges,0) * 1) as badge_stats_weight
        from badge_stats bs
    ) b on b.user_id = ru.user_id
),
users_enriched as (
    select
        ru.*,
        ua.questions,
        ua.answers,
        ua.total_post_score,
        ua.closed_posts,
        ua.avg_views_per_post,
        ua.total_posts,
        ua.last_activity,
        coalesce(aa.accepted_answers, 0) as accepted_answers,
        coalesce(cs.comments_count, 0) as comments_count,
        coalesce(cs.high_scored_comments, 0) as high_scored_comments,
        cs.last_comment_date,
        coalesce(bs.total_badges, 0) as total_badges,
        coalesce(bs.gold_badges, 0) as gold_badges,
        coalesce(bs.silver_badges, 0) as silver_badges,
        coalesce(bs.bronze_badges, 0) as bronze_badges,
        coalesce(bs.tag_badges, 0) as tag_badges,
        bs.first_badge_date,
        bs.last_badge_date,
        ut.top_tags_by_popularity,
        ut.user_tag_set,
        ut.distinct_tags_used,
        qm.questions_count,
        qm.avg_q_score,
        qm.questions_with_accepted,
        qm.total_q_views,
        qm.q_upvotes,
        qm.q_downvotes,
        qm.q_mod_actions,
        qm.q_duplicate_links,
        am.answers_count,
        am.avg_a_score,
        am.a_upvotes,
        am.a_downvotes,
        am.a_mod_actions,
        ra.most_recent_post_id,
        ra.most_recent_post_date,
        ra.most_recent_post_score,
        ra.cumulative_score_latest,
        ra.moving_avg_score_11_latest
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join answer_accepts aa on aa.user_id = ru.user_id
    left join comment_stats cs on cs.user_id = ru.user_id
    left join badge_stats bs on bs.user_id = ru.user_id
    left join user_top_tags ut on ut.user_id = ru.user_id
    left join question_metrics qm on qm.user_id = ru.user_id
    left join answer_metrics am on am.user_id = ru.user_id
    left join recent_activity ra on ra.user_id = ru.user_id
),
ranked as (
    select
        ue.*,
        es.engagement_score_raw,
        dense_rank() over (
            order by
                coalesce(es.engagement_score_raw, -1e9) desc,
                coalesce(ue.reputation, -1) desc,
                coalesce(ue.total_posts, -1) desc,
                ue.user_id asc
        ) as engagement_rank,
        ntile(10) over (order by coalesce(es.engagement_score_raw, -1e9) desc) as engagement_decile
    from users_enriched ue
    left join engagement_score es on es.user_id = ue.user_id
),
filtered as (
    select
        r.*
    from ranked r
    where
        coalesce(r.total_posts, 0) >= 5
        and coalesce(r.questions_count, 0) >= 1
        and coalesce(r.answers_count, 0) >= 1
        and (
            r.most_recent_post_date >= now() - interval '180 days'
            or r.last_activity >= now() - interval '180 days'
        )
        and (
            r.websiteurl_norm is null
            or r.websiteurl_norm not ilike any (array['%spam%', '%test%', '%example%'])
        )
),
final_agg as (
    select
        f.user_id,
        f.displayname,
        f.location,
        f.reputation,
        f.engagement_rank,
        f.engagement_decile,
        f.engagement_score_raw,
        f.questions_count,
        f.answers_count,
        f.accepted_answers,
        f.questions_with_accepted,
        f.total_posts,
        f.total_post_score,
        f.q_upvotes + f.a_upvotes as total_upvotes,
        f.q_downvotes + f.a_downvotes as total_downvotes,
        coalesce(f.total_q_views, 0) as total_q_views,
        f.closed_posts,
        f.q_duplicate_links,
        f.q_mod_actions + f.a_mod_actions as total_mod_actions,
        f.comments_count,
        f.high_scored_comments,
        f.distinct_tags_used,
        coalesce(array_to_string(f.top_tags_by_popularity[1:5], ', '), '') as top5_tags,
        case
            when f.reputation >= 10000 then 'Legend'
            when f.reputation >= 5000 then 'Expert'
            when f.reputation >= 2000 then 'Advanced'
            when f.reputation >= 500 then 'Intermediate'
            else 'Rookie'
        end as rep_band,
        case
            when f.questions_with_accepted >= greatest(1, f.questions_count / 2) then 'Helpful Asker'
            when f.accepted_answers >= greatest(1, f.answers_count / 4) then 'Helpful Answerer'
            else 'Contributor'
        end as role_hint,
        f.most_recent_post_id,
        f.most_recent_post_date,
        f.most_recent_post_score,
        f.cumulative_score_latest,
        f.moving_avg_score_11_latest
    from filtered f
)
select
    fa.*,
    -- correlated subquery: earliest activity date across posts/comments per user
    least(
        coalesce((select min(p.creationdate) from posts p where p.owneruserid = fa.user_id), timestamp '9999-12-31'),
        coalesce((select min(c.creationdate) from comments c where c.userid = fa.user_id), timestamp '9999-12-31')
    ) as earliest_activity,
    -- set operator based comparison: whether user has any tag wiki ownership
    exists (
        select 1
        from posts pw
        where pw.owneruserid = fa.user_id and pw.posttypeid in (4,5)
        intersect
        select 1
        from posts px
        where px.owneruserid = fa.user_id
    ) as has_tag_wiki_authorship,
    -- complex predicate derived flag
    case
        when coalesce(fa.total_upvotes,0) >= 10
         and coalesce(fa.total_downvotes,0) <= fa.total_upvotes / 4
         and coalesce(fa.closed_posts,0) = 0
         and fa.engagement_decile <= 3
        then true else false
    end as clean_highly_engaged
from final_agg fa
order by fa.engagement_rank, fa.user_id
limit 250;