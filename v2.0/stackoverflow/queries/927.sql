with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
    from users u
    where u.creationdate >= (
        select date_trunc('year', max(creationdate)) - interval '2 years' from users
    )
),
q_posts as (
    select
        p.id as question_id,
        p.owneruserid as asker_id,
        p.creationdate as question_date,
        p.score as question_score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate
    from posts p
    where p.posttypeid = 1
),
a_posts as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answer_date,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
badges_by_user as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when coalesce(b.tagbased, false) = true then 1 else 0 end) as tag_badges
    from badges b
    where b.date >= (
        select date_trunc('year', max(date)) - interval '5 years' from badges
    )
    group by b.userid
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    where v.creationdate >= (
        select date_trunc('year', max(creationdate)) - interval '3 years' from votes
    )
    group by v.postid
),
comments_agg as (
    select
        c.postid,
        count(*) as comment_count,
        avg(nullif(c.score,0)) as avg_nonzero_comment_score
    from comments c
    where c.creationdate >= (
        select date_trunc('year', max(creationdate)) - interval '3 years' from comments
    )
    group by c.postid
),
ph_events as (
    select
        ph.postid,
        sum(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as close_events,
        sum(case when ph.posthistorytypeid in (11,13) then 1 else 0 end) as reopen_undelete_events,
        max(case when ph.posthistorytypeid in (10,35) then ph.creationdate end) as last_close_event_at,
        max(case when ph.posthistorytypeid in (11,13) then ph.creationdate end) as last_reopen_undelete_at,
        max(case when ph.posthistorytypeid in (10,35) then
                case
                    when trim(coalesce(ph.comment, '')) = '' then null
                    when ph.comment ~ '^[0-9]+$' then cast(ph.comment as integer)
                    else null
                end
            end) as last_close_reason_id
    from posthistory ph
    where ph.creationdate >= (
        select date_trunc('year', max(creationdate)) - interval '4 years' from posthistory
    )
    group by ph.postid
),
dup_links as (
    select
        pl.postid as dup_question_id,
        count(*) filter (where pl.linktypeid = 3) as duplicate_of_cnt,
        count(*) filter (where pl.linktypeid = 1) as linked_cnt,
        max(pl.creationdate) as last_link_at
    from postlinks pl
    group by pl.postid
),
tag_expansion as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag_name
    from q_posts q
    where q.tags is not null and q.tags <> ''
),
tag_rank as (
    select
        te.tag_name,
        count(*) as q_count,
        percent_rank() over (order by count(*) desc) as popularity_pr
    from tag_expansion te
    group by te.tag_name
),
question_metrics as (
    select
        q.question_id,
        q.asker_id,
        q.question_date,
        q.question_score,
        q.viewcount,
        q.acceptedanswerid,
        q.closeddate,
        vaq.upvotes as q_upvotes,
        vaq.downvotes as q_downvotes,
        vaq.favorites as q_favorites,
        coalesce(vaq.bounty_total,0) as q_bounty_total,
        caq.comment_count as q_comment_count,
        caq.avg_nonzero_comment_score as q_avg_comment_score,
        phe.close_events,
        phe.reopen_undelete_events,
        phe.last_close_event_at,
        phe.last_reopen_undelete_at,
        crt.name as last_close_reason_name,
        dl.duplicate_of_cnt,
        dl.linked_cnt,
        dl.last_link_at,
        array_agg(distinct te.tag_name) as tags_array,
        avg(tr.popularity_pr) as avg_tag_popularity_pr
    from q_posts q
    left join votes_agg vaq on vaq.postid = q.question_id
    left join comments_agg caq on caq.postid = q.question_id
    left join ph_events phe on phe.postid = q.question_id
    left join closereasontypes crt on crt.id = phe.last_close_reason_id
    left join dup_links dl on dl.dup_question_id = q.question_id
    left join tag_expansion te on te.question_id = q.question_id
    left join tag_rank tr on tr.tag_name = te.tag_name
    group by
        q.question_id, q.asker_id, q.question_date, q.question_score, q.viewcount, q.acceptedanswerid, q.closeddate,
        vaq.upvotes, vaq.downvotes, vaq.favorites, vaq.bounty_total,
        caq.comment_count, caq.avg_nonzero_comment_score,
        phe.close_events, phe.reopen_undelete_events, phe.last_close_event_at, phe.last_reopen_undelete_at, crt.name,
        dl.duplicate_of_cnt, dl.linked_cnt, dl.last_link_at
),
answer_metrics as (
    select
        a.answer_id,
        a.question_id,
        a.answerer_id,
        a.answer_date,
        a.answer_score,
        va.upvotes as a_upvotes,
        va.downvotes as a_downvotes,
        coalesce(va.bounty_total,0) as a_bounty_total,
        ca.comment_count as a_comment_count
    from a_posts a
    left join votes_agg va on va.postid = a.answer_id
    left join comments_agg ca on ca.postid = a.answer_id
),
accepted_answer as (
    select
        q.question_id,
        am.answer_id as accepted_answer_id,
        am.answerer_id as accepted_answerer_id,
        am.answer_date as accepted_answer_date,
        am.answer_score as accepted_answer_score,
        am.a_upvotes as accepted_answer_upvotes,
        am.a_downvotes as accepted_answer_downvotes
    from question_metrics q
    join answer_metrics am on am.answer_id = q.acceptedanswerid
),
first_answer_per_question as (
    select
        am.question_id,
        am.answer_id as first_answer_id,
        am.answerer_id as first_answerer_id,
        am.answer_date as first_answer_date,
        am.answer_score as first_answer_score,
        row_number() over (partition by am.question_id order by am.answer_date) as rn
    from answer_metrics am
),
answer_speeds as (
    select
        q.question_id,
        extract(epoch from (fa.first_answer_date - q.question_date)) as sec_to_first_answer,
        extract(epoch from (aa.accepted_answer_date - q.question_date)) as sec_to_accepted_answer
    from question_metrics q
    left join first_answer_per_question fa on fa.question_id = q.question_id and fa.rn = 1
    left join accepted_answer aa on aa.question_id = q.question_id
),
user_rollup as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.websiteurl_norm,
        coalesce(b.total_badges,0) as total_badges,
        coalesce(b.gold_badges,0) as gold_badges,
        coalesce(b.silver_badges,0) as silver_badges,
        coalesce(b.bronze_badges,0) as bronze_badges,
        coalesce(b.tag_badges,0) as tag_badges
    from recent_users u
    left join badges_by_user b on b.userid = u.user_id
),
user_q_stats as (
    select
        qm.asker_id as user_id,
        count(*) as questions_asked,
        avg(qm.question_score) as avg_q_score,
        avg(qm.q_upvotes - qm.q_downvotes) as avg_q_net_votes,
        avg(qm.viewcount) as avg_q_views,
        avg(coalesce(asl.sec_to_first_answer, 86400*7)) as avg_sec_to_first_answer_capped,
        avg(coalesce(asl.sec_to_accepted_answer, 86400*14)) as avg_sec_to_accepted_answer_capped,
        sum(case when qm.closeddate is not null then 1 else 0 end) as q_closed_cnt,
        sum(coalesce(qm.duplicate_of_cnt,0)) as q_dup_links
    from question_metrics qm
    left join answer_speeds asl on asl.question_id = qm.question_id
    group by qm.asker_id
),
user_a_stats as (
    select
        am.answerer_id as user_id,
        count(*) as answers_posted,
        avg(am.answer_score) as avg_a_score,
        avg(am.a_upvotes - am.a_downvotes) as avg_a_net_votes,
        sum(am.a_bounty_total) as bounty_earned
    from answer_metrics am
    group by am.answerer_id
),
title_patterns as (
    select
        q.question_id,
        case
            when lower(q.title) like '%how to%' then 'how_to'
            when q.title ~* '^\s*\[.*\]' then 'tag_bracketed'
            when length(coalesce(q.title,'')) > 150 then 'very_long'
            when lower(q.title) like '% vs %' then 'versus'
            else 'other'
        end as title_bucket
    from q_posts q
),
title_bucket_stats as (
    select
        tp.title_bucket,
        count(*) as bucket_count,
        avg(qm.question_score) as bucket_avg_score,
        avg(qm.q_upvotes - qm.q_downvotes) as bucket_avg_net_votes
    from title_patterns tp
    join question_metrics qm on qm.question_id = tp.question_id
    group by tp.title_bucket
),
final_users as (
    select
        ur.*,
        coalesce(qs.questions_asked,0) as questions_asked,
        qs.avg_q_score,
        qs.avg_q_net_votes,
        qs.avg_q_views,
        qs.avg_sec_to_first_answer_capped,
        qs.avg_sec_to_accepted_answer_capped,
        coalesce(qs.q_closed_cnt,0) as q_closed_cnt,
        coalesce(qs.q_dup_links,0) as q_dup_links,
        coalesce(as2.answers_posted,0) as answers_posted,
        as2.avg_a_score,
        as2.avg_a_net_votes,
        coalesce(as2.bounty_earned,0) as bounty_earned
    from user_rollup ur
    left join user_q_stats qs on qs.user_id = ur.user_id
    left join user_a_stats as2 on as2.user_id = ur.user_id
),
ranked_users as (
    select
        fu.*,
        dense_rank() over (order by coalesce(answers_posted,0) desc, coalesce(questions_asked,0) desc, reputation desc) as contrib_rank,
        ntile(5) over (order by coalesce(avg_q_net_votes,0) desc) as q_quality_quintile,
        ntile(5) over (order by coalesce(avg_a_net_votes,0) desc) as a_quality_quintile
    from final_users fu
),
recent_activity as (
    select
        u.user_id,
        max(p.lastactivitydate) as last_post_activity,
        max(c.creationdate) as last_comment_activity
    from recent_users u
    left join posts p on p.owneruserid = u.user_id
    left join comments c on c.userid = u.user_id
    group by u.user_id
),
tag_affinity as (
    select
        qm.asker_id as user_id,
        te.tag_name,
        count(*) as q_cnt,
        row_number() over (partition by qm.asker_id order by count(*) desc, min(qm.question_id)) as rn
    from question_metrics qm
    join tag_expansion te on te.question_id = qm.question_id
    group by qm.asker_id, te.tag_name
),
top_tag as (
    select user_id, tag_name as top_tag_name, q_cnt as top_tag_q_cnt
    from tag_affinity
    where rn = 1
),
null_logic_demo as (
    select
        ru.user_id,
        case
            when coalesce(trim(ru.location), '') = '' then null
            when lower(ru.location) similar to '%(remote|anywhere)%' then 'Remote'
            else ru.location
        end as normalized_location
    from recent_users ru
)
select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate as user_creationdate,
    coalesce(nld.normalized_location, 'Unspecified') as normalized_location,
    ru.websiteurl_norm,
    ru.total_badges,
    ru.gold_badges,
    ru.silver_badges,
    ru.bronze_badges,
    ru.tag_badges,
    ru.questions_asked,
    ru.answers_posted,
    ru.avg_q_score,
    ru.avg_a_score,
    ru.avg_q_net_votes,
    ru.avg_a_net_votes,
    ru.avg_q_views,
    ru.avg_sec_to_first_answer_capped,
    ru.avg_sec_to_accepted_answer_capped,
    ru.q_closed_cnt,
    ru.q_dup_links,
    ru.bounty_earned,
    ru.contrib_rank,
    ru.q_quality_quintile,
    ru.a_quality_quintile,
    ra.last_post_activity,
    ra.last_comment_activity,
    tt.top_tag_name,
    tt.top_tag_q_cnt,
    ts.title_bucket,
    tbs.bucket_count as title_bucket_count,
    tbs.bucket_avg_score as title_bucket_avg_score,
    tbs.bucket_avg_net_votes as title_bucket_avg_net_votes
from ranked_users ru
left join recent_activity ra on ra.user_id = ru.user_id
left join top_tag tt on tt.user_id = ru.user_id
left join title_patterns ts on ts.question_id = (
    select q.question_id
    from question_metrics q
    where q.asker_id = ru.user_id
    order by q.viewcount desc nulls last, q.question_score desc nulls last, q.question_id
    limit 1
)
left join title_bucket_stats tbs on tbs.title_bucket = ts.title_bucket
left join null_logic_demo nld on nld.user_id = ru.user_id
where
    (
        coalesce(ru.answers_posted,0) > 0
        or coalesce(ru.questions_asked,0) > 0
        or coalesce(ru.total_badges,0) >= 3
    )
    and coalesce(ru.avg_q_net_votes, 0) + coalesce(ru.avg_a_net_votes, 0) > -5
    and (
        tt.top_tag_name is null
        or (
            tt.top_tag_name not ilike 'test%' 
            and tt.top_tag_name not ilike 'debug%' 
            and tt.top_tag_name not ilike 'homework%'
        )
    )
order by
    ru.contrib_rank,
    coalesce(ru.answers_posted,0) desc,
    coalesce(ru.questions_asked,0) desc,
    ru.reputation desc
limit 500;