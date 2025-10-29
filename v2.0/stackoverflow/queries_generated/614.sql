-- {"query": "614.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2668} 
with top_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        date_trunc('month', u.creationdate) as cohort_month,
        coalesce(nullif(b.total_badges, 0), 0) as total_badges,
        row_number() over (order by u.reputation desc, u.id) as rn_global
    from users u
    left join (
        select userId, count(*) as total_badges
        from badges
        group by userId
    ) b on b.userid = u.id
    where u.reputation > (
        select percentile_disc(0.9) within group (order by reputation) from users
    )
),
questions as (
    select
        p.id as question_id,
        p.owneruserid as owner_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.favoritecount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.commentcount,
        dense_rank() over (order by coalesce(p.viewcount, 0) desc, p.id) as dr_views
    from posts p
    where p.posttypeid = 1
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as owner_id,
        a.creationdate,
        a.score,
        row_number() over (partition by a.parentid order by a.score desc, a.creationdate asc, a.id) as rn_score
    from posts a
    where a.posttypeid = 2
),
qa as (
    select
        q.question_id,
        q.owner_id as asker_id,
        q.creationdate as q_created,
        q.score as q_score,
        q.viewcount,
        q.answercount,
        q.favoritecount,
        q.title,
        q.tags,
        q.acceptedanswerid,
        q.closeddate,
        q.commentcount,
        a.answer_id,
        a.owner_id as answerer_id,
        a.creationdate as a_created,
        a.score as a_score,
        case when q.acceptedanswerid = a.answer_id then 1 else 0 end as is_accepted
    from questions q
    left join answers a
      on a.question_id = q.question_id
),
vote_aggs as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        max(case when v.votetypeid in (8,9) then v.bountyamount else null end) as max_bounty
    from votes v
    group by v.postid
),
link_dupes as (
    select
        pl.postid as question_id,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as related_links
    from postlinks pl
    group by pl.postid
),
close_events as (
    select
        ph.postid as question_id,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 11) as first_reopened,
        max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) else null end) as close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
tag_expansion as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
    from questions q
    where q.tags is not null and q.tags like '<%>'
),
tag_stats as (
    select
        te.question_id,
        array_agg(te.tag order by te.tag) as tag_list,
        count(*) as tag_count,
        sum(case when te.tag ~* 'sql|postgres|mysql|sqlite|tsql' then 1 else 0 end) as is_db_related_count
    from tag_expansion te
    group by te.question_id
),
comment_agg as (
    select
        c.postid as post_id,
        count(*) as comment_count,
        max(c.score) as max_comment_score,
        max(length(c.text)) as max_comment_length,
        min(c.creationdate) as first_comment_at
    from comments c
    group by c.postid
),
user_post_activity as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(p.score) as total_score,
        sum(coalesce(p.viewcount,0)) as total_views,
        count(*) as total_posts,
        max(p.lastactivitydate) as last_post_activity_at
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
accepted_answer_latency as (
    select
        q.id as question_id,
        q.creationdate as q_created,
        a.id as accepted_answer_id,
        a.creationdate as a_created,
        extract(epoch from (a.creationdate - q.creationdate)) as seconds_to_accept
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
),
ranked_questions as (
    select
        q.question_id,
        q.viewcount,
        q.score as q_score,
        coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as net_votes,
        sqrt(greatest(coalesce(q.viewcount,0),1)) * ln(greatest(coalesce(va.upvotes,0)+1,1)) as hotness_metric,
        row_number() over (order by sqrt(greatest(coalesce(q.viewcount,0),1)) * ln(greatest(coalesce(va.upvotes,0)+1,1)) desc, q.question_id) as rn_hot
    from questions q
    left join vote_aggs va on va.postid = q.question_id
),
power_users as (
    select
        tu.user_id,
        tu.displayname,
        tu.reputation,
        upa.q_count,
        upa.a_count,
        upa.total_score,
        upa.total_views,
        rank() over (order by (coalesce(upa.a_count,0) + 0.5*coalesce(upa.q_count,0)) desc, tu.reputation desc) as activity_rank
    from top_users tu
    left join user_post_activity upa on upa.user_id = tu.user_id
),
post_type_names as (
    select id, name from posttypes
),
final_candidates as (
    select
        qa.question_id,
        qa.answer_id,
        qa.asker_id,
        qa.answerer_id,
        qa.q_created,
        qa.a_created,
        qa.q_score,
        qa.a_score,
        qa.viewcount,
        qa.answercount,
        qa.favoritecount,
        qa.title,
        ts.tag_list,
        ts.tag_count,
        case when ts.is_db_related_count > 0 then 1 else 0 end as is_db_related,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.favorites,0) as votes_favorites,
        coalesce(va.max_bounty,0) as max_bounty,
        coalesce(ld.duplicate_links,0) as duplicate_links,
        coalesce(ld.related_links,0) as related_links,
        ce.first_closed,
        ce.first_reopened,
        ce.close_reason_id,
        ca.comment_count as comment_count_join,
        ca.max_comment_score,
        ca.max_comment_length,
        aal.seconds_to_accept,
        rq.hotness_metric,
        rq.rn_hot,
        row_number() over (partition by qa.question_id order by qa.is_accepted desc, qa.a_score desc nulls last, qa.a_created asc nulls last) as rn_answer_pref
    from qa
    left join vote_aggs va on va.postid = qa.question_id
    left join link_dupes ld on ld.question_id = qa.question_id
    left join close_events ce on ce.question_id = qa.question_id
    left join tag_stats ts on ts.question_id = qa.question_id
    left join comment_agg ca on ca.post_id = qa.question_id
    left join accepted_answer_latency aal on aal.question_id = qa.question_id
    left join ranked_questions rq on rq.question_id = qa.question_id
)
select
    fc.question_id,
    p_q.title as question_title,
    coalesce(p_q.ownerdisplayname, u_q.displayname, '[unknown]') as asker_name,
    coalesce(p_a.ownerdisplayname, u_a.displayname, '[unknown]') as answerer_name,
    ptn_q.name as post_type_question,
    ptn_a.name as post_type_answer,
    fc.q_created,
    fc.a_created,
    fc.q_score,
    fc.a_score,
    fc.viewcount,
    fc.answercount,
    fc.favoritecount,
    fc.upvotes,
    fc.downvotes,
    fc.votes_favorites,
    fc.max_bounty,
    fc.duplicate_links,
    fc.related_links,
    fc.first_closed,
    fc.first_reopened,
    crt.name as close_reason_name,
    fc.seconds_to_accept,
    fc.hotness_metric,
    fc.rn_hot,
    fc.tag_list,
    fc.tag_count,
    fc.is_db_related,
    coalesce(ca.comment_count, 0) as total_comment_count,
    coalesce(ca.first_comment_at, null) as first_comment_at,
    pu.displayname as power_user_name,
    pu.activity_rank,
    sum(case when fc.a_score > 0 then 1 else 0 end) over (partition by fc.question_id) as positive_answers_count,
    avg(fc.a_score) filter (where fc.a_score is not null) over (partition by fc.question_id) as avg_answer_score_per_q,
    rank() over (order by fc.hotness_metric desc nulls last, fc.viewcount desc nulls last) as overall_hot_rank
from final_candidates fc
left join posts p_q on p_q.id = fc.question_id
left join posts p_a on p_a.id = fc.answer_id
left join users u_q on u_q.id = fc.asker_id
left join users u_a on u_a.id = fc.answerer_id
left join post_type_names ptn_q on ptn_q.id = p_q.posttypeid
left join post_type_names ptn_a on ptn_a.id = p_a.posttypeid
left join closeresontypes crt on crt.id = coalesce(fc.close_reason_id, 0)
left join comment_agg ca on ca.post_id = fc.question_id
left join power_users pu on pu.user_id = fc.asker_id
where
    (fc.rn_answer_pref = 1 or fc.answer_id is null)
    and coalesce(fc.viewcount, 0) > 0
    and (
        fc.is_db_related = 1
        or (
            fc.tag_count >= 3
            and (fc.upvotes - fc.downvotes) >= 1
        )
        or (
            fc.max_bounty >= 100
            and fc.seconds_to_accept is not null
        )
    )
    and (
        fc.first_closed is null
        or (fc.first_reopened is not null and fc.first_reopened > fc.first_closed)
        or fc.close_reason_id in (101, 102, 103, 104, 105)
    )
    and (
        not exists (
            select 1
            from postlinks plx
            where plx.postid = fc.question_id
              and plx.linktypeid = 3
              and plx.relatedpostid = any (
                    select pl2.relatedpostid
                    from postlinks pl2
                    where pl2.postid = fc.question_id
                      and pl2.linktypeid = 1
              )
        )
    )
order by
    overall_hot_rank,
    fc.question_id
limit 500;