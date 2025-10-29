-- {"query": "446.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3324}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.websiteurl,
        u.upvotes,
        u.downvotes,
        u.views,
        row_number() over (order by u.creationdate desc, u.id) as rn
    from users u
),
active_questions as (
    select
        p.id as question_id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        p.favoritecount,
        p.closeddate,
        p.lastactivitydate,
        coalesce(nullif(trim(p.tags), ''), '[]') as normalized_tags
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '6 months' from posts where posttypeid = 1)
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answer_created,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
q_badges as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) as total_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
vote_agg as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        count(*) filter (where v.votetypeid = 5) as favorites
    from votes v
    group by v.postid
),
comment_agg as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.creationdate) as last_comment_at,
        max(length(c.text)) as longest_comment_len
    from comments c
    group by c.postid
),
link_agg as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        count(*) filter (where pl.linktypeid = 3) as duplicate_count,
        count(*) as total_link_refs
    from postlinks pl
    group by pl.postid
),
history_flags as (
    select
        ph.postid,
        max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as was_closed_or_migrated,
        max(case when ph.posthistorytypeid in (11) then 1 else 0 end) as was_reopened,
        max(case when ph.posthistorytypeid in (19) then 1 else 0 end) as was_protected,
        max(case when ph.posthistorytypeid in (50) then 1 else 0 end) as was_community_bump,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events
    from posthistory ph
    group by ph.postid
),
tag_expanded as (
    select
        aq.question_id,
        unnest(string_to_array(substring(aq.tags, 2, greatest(length(aq.tags)-2,0)), '><')) as tag
    from active_questions aq
    where aq.tags is not null and length(aq.tags) >= 2
),
tag_stats as (
    select
        te.question_id,
        array_agg(te.tag order by te.tag) as tag_list,
        count(*) as tag_count,
        sum(case when lower(te.tag) like '%' || 'sql' || '%' then 1 else 0 end) as sql_tag_matches
    from tag_expanded te
    group by te.question_id
),
question_quality as (
    select
        aq.question_id,
        aq.owneruserid,
        aq.creationdate,
        aq.score,
        aq.viewcount,
        aq.title,
        aq.answercount,
        aq.favoritecount,
        aq.closeddate,
        aq.lastactivitydate,
        ts.tag_list,
        ts.tag_count,
        ts.sql_tag_matches,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.bounty_total,0) as bounty_total,
        coalesce(va.favorites,0) as vote_favorites,
        coalesce(ca.comment_count,0) as comment_count,
        ca.last_comment_at,
        coalesce(ca.longest_comment_len,0) as longest_comment_len,
        coalesce(la.linked_count,0) as linked_count,
        coalesce(la.duplicate_count,0) as duplicate_count,
        coalesce(hf.was_closed_or_migrated,0) as was_closed_or_migrated,
        coalesce(hf.was_reopened,0) as was_reopened,
        coalesce(hf.was_protected,0) as was_protected,
        coalesce(hf.was_community_bump,0) as was_community_bump,
        coalesce(hf.edit_events,0) as edit_events
    from active_questions aq
    left join tag_stats ts on ts.question_id = aq.question_id
    left join vote_agg va on va.postid = aq.question_id
    left join comment_agg ca on ca.postid = aq.question_id
    left join link_agg la on la.postid = aq.question_id
    left join history_flags hf on hf.postid = aq.question_id
),
answer_stats as (
    select
        a.question_id,
        count(*) as answers_total,
        count(*) filter (where a.answer_score > 0) as answers_positive,
        max(a.answer_score) as max_answer_score,
        min(a.answer_score) as min_answer_score,
        avg(a.answer_score) as avg_answer_score,
        max(a.answer_created) as last_answer_at
    from answers a
    group by a.question_id
),
owner_activity as (
    select
        u.id as user_id,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as q_count,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as a_count,
        avg(nullif(p.score,0)) filter (where p.posttypeid in (1,2)) as avg_nonzero_score,
        max(p.lastactivitydate) as last_post_activity
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
ranked_questions as (
    select
        qq.question_id,
        qq.owneruserid,
        qq.creationdate,
        qq.score,
        qq.viewcount,
        qq.title,
        qq.answercount,
        qq.favoritecount,
        qq.closeddate,
        qq.lastactivitydate,
        qq.tag_list,
        qq.tag_count,
        qq.sql_tag_matches,
        qq.upvotes,
        qq.downvotes,
        qq.bounty_total,
        qq.vote_favorites,
        qq.comment_count,
        qq.last_comment_at,
        qq.longest_comment_len,
        qq.linked_count,
        qq.duplicate_count,
        qq.was_closed_or_migrated,
        qq.was_reopened,
        qq.was_protected,
        qq.was_community_bump,
        qq.edit_events,
        coalesce(ans.answers_total,0) as answers_total,
        coalesce(ans.answers_positive,0) as answers_positive,
        coalesce(ans.max_answer_score,0) as max_answer_score,
        coalesce(ans.min_answer_score,0) as min_answer_score,
        ans.avg_answer_score,
        ans.last_answer_at,
        case
            when qq.closeddate is not null then 0
            when qq.duplicate_count > 0 then 0.25
            else 1
        end
        * (
            greatest(qq.score,0) * 2
            + least(greatest(qq.viewcount,0), 100000) / 500.0
            + coalesce(qq.vote_favorites,0) * 1.5
            + coalesce(qq.upvotes - qq.downvotes,0) * 0.5
            + coalesce(qq.bounty_total,0) / 100.0
            + coalesce(coalesce(ans.answers_positive,0),0) * 1.25
            + case when qq.sql_tag_matches > 0 then 3 else 0 end
            + least(coalesce(qq.edit_events,0), 10) * 0.3
            + case when qq.was_protected = 1 then -2 else 0 end
        ) as quality_score
    from question_quality qq
    left join answer_stats ans on ans.question_id = qq.question_id
),
user_enriched as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.websiteurl,
        u.upvotes,
        u.downvotes,
        u.views,
        oa.q_count,
        oa.a_count,
        oa.avg_nonzero_score,
        oa.last_post_activity,
        qb.gold_badges,
        qb.silver_badges,
        qb.bronze_badges,
        qb.total_badges,
        qb.last_badge_date,
        ntile(10) over (order by coalesce(qb.total_badges,0) desc, u.reputation desc, u.views desc) as decile_engagement
    from recent_users u
    left join owner_activity oa on oa.user_id = u.user_id
    left join q_badges qb on qb.userid = u.user_id
),
question_owner_join as (
    select
        rq.question_id,
        rq.quality_score,
        rq.score as q_score,
        rq.viewcount as q_views,
        rq.answercount as q_answercount,
        rq.tag_count,
        rq.sql_tag_matches,
        rq.was_closed_or_migrated,
        rq.was_reopened,
        rq.was_protected,
        ue.user_id as owner_id,
        ue.displayname as owner_name,
        ue.reputation as owner_reputation,
        ue.total_badges,
        ue.decile_engagement
    from ranked_questions rq
    left join users u on u.id = rq.owneruserid
    left join user_enriched ue on ue.user_id = u.id
),
dup_clusters as (
    select
        rq.question_id,
        count(distinct pl.relatedpostid) filter (where pl.linktypeid = 3) as dup_targets,
        min(pl.creationdate) filter (where pl.linktypeid = 3) as first_dup_mark
    from ranked_questions rq
    left join postlinks pl on pl.postid = rq.question_id
    group by rq.question_id
),
normalized_title as (
    select
        rq.question_id,
        regexp_replace(lower(coalesce(rq.title,'')), '\s+', ' ', 'g') as norm_title,
        length(coalesce(rq.title,'')) as title_len
    from ranked_questions rq
),
title_similarity as (
    select
        n1.question_id as q1,
        n2.question_id as q2,
        case
            when n1.question_id = n2.question_id then 1.0
            else
                greatest(0.0,
                    1.0 - abs(length(n1.norm_title) - length(n2.norm_title)) / nullif(greatest(length(n1.norm_title), length(n2.norm_title)),0)
                )
        end as crude_len_sim
    from normalized_title n1
    join normalized_title n2
      on n1.title_len between n2.title_len - 20 and n2.title_len + 20
     and n1.question_id < n2.question_id
),
owner_recent_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as posts_30d,
        count(*) filter (where p.posttypeid = 1 and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as questions_30d,
        count(*) filter (where p.posttypeid = 2 and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as answers_30d,
        max(p.lastactivitydate) as last_any_activity
    from posts p
    group by p.owneruserid
),
final as (
    select
        qoj.question_id,
        qoj.quality_score,
        qoj.q_score,
        qoj.q_views,
        qoj.q_answercount,
        qoj.tag_count,
        qoj.sql_tag_matches,
        qoj.was_closed_or_migrated,
        qoj.was_reopened,
        qoj.was_protected,
        qoj.owner_id,
        qoj.owner_name,
        qoj.owner_reputation,
        qoj.total_badges,
        qoj.decile_engagement,
        coalesce(dc.dup_targets,0) as dup_targets,
        dc.first_dup_mark,
        avg(ts.crude_len_sim) filter (where ts.crude_len_sim < 1) as avg_title_len_similarity_to_others,
        count(ts.q2) as comparable_title_peers,
        ora.posts_30d,
        ora.questions_30d,
        ora.answers_30d,
        ora.last_any_activity,
        case
            when qoj.was_closed_or_migrated = 1 then 'closed_or_migrated'
            when qoj.was_protected = 1 then 'protected'
            when qoj.q_answercount = 0 and qoj.q_views > 5000 then 'unanswered_high_view'
            when qoj.sql_tag_matches > 0 then 'sql_related'
            else 'other'
        end as bucket,
        row_number() over (partition by case
            when qoj.was_closed_or_migrated = 1 then 'closed_or_migrated'
            when qoj.was_protected = 1 then 'protected'
            when qoj.q_answercount = 0 and qoj.q_views > 5000 then 'unanswered_high_view'
            when qoj.sql_tag_matches > 0 then 'sql_related'
            else 'other'
        end order by qoj.quality_score desc, qoj.q_views desc, qoj.question_id desc) as bucket_rank,
        dense_rank() over (order by qoj.quality_score desc) as global_rank
    from question_owner_join qoj
    left join dup_clusters dc on dc.question_id = qoj.question_id
    left join title_similarity ts on ts.q1 = qoj.question_id
    left join owner_recent_activity ora on ora.user_id = qoj.owner_id
    group by
        qoj.question_id,
        qoj.quality_score,
        qoj.q_score,
        qoj.q_views,
        qoj.q_answercount,
        qoj.tag_count,
        qoj.sql_tag_matches,
        qoj.was_closed_or_migrated,
        qoj.was_reopened,
        qoj.was_protected,
        qoj.owner_id,
        qoj.owner_name,
        qoj.owner_reputation,
        qoj.total_badges,
        qoj.decile_engagement,
        dc.dup_targets,
        dc.first_dup_mark,
        ora.posts_30d,
        ora.questions_30d,
        ora.answers_30d,
        ora.last_any_activity
)
select
    f.question_id,
    f.owner_id,
    f.owner_name,
    f.owner_reputation,
    f.total_badges,
    f.decile_engagement,
    f.quality_score,
    f.q_score,
    f.q_views,
    f.q_answercount,
    f.tag_count,
    f.sql_tag_matches,
    f.dup_targets,
    f.first_dup_mark,
    f.avg_title_len_similarity_to_others,
    f.comparable_title_peers,
    f.posts_30d,
    f.questions_30d,
    f.answers_30d,
    f.last_any_activity,
    f.bucket,
    f.bucket_rank,
    f.global_rank
from final f
where (
    f.bucket = 'sql_related'
    or (f.bucket = 'unanswered_high_view' and f.quality_score > 5)
    or (f.bucket = 'other' and f.quality_score > 15 and coalesce(f.dup_targets,0) = 0)
)
and (f.owner_reputation is null or f.owner_reputation >= 100)
and not (lower(f.owner_name) like '%community%' and f.owner_id = -1)
order by f.global_rank, f.bucket, f.bucket_rank
limit 250;