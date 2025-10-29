-- {"query": "102.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2959} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_newest,
        ntile(10) over (order by u.reputation desc nulls last) as rep_decile
    from users u
),
question_posts as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.communityowneddate,
        p.answercount,
        p.favoritecount
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select
        p.id as answer_id,
        p.parentid as question_id,
        p.owneruserid as user_id,
        p.creationdate as answer_creation,
        p.score as answer_score
    from posts p
    where p.posttypeid = 2
),
user_firsts as (
    select
        qp.user_id,
        min(qp.creationdate) as first_question_date,
        min(ap.answer_creation) as first_answer_date
    from question_posts qp
    full outer join answer_posts ap
        on ap.user_id = qp.user_id
    group by coalesce(qp.user_id, ap.user_id)
),
tag_expansion as (
    select
        qp.post_id,
        lower(trim(tg)) as tag
    from question_posts qp
    cross join lateral unnest(string_to_array(substring(coalesce(qp.tags, ''), 2, greatest(length(coalesce(qp.tags, ''))-2, 0)), '><')) as tg
),
hot_questions as (
    select
        qp.post_id,
        qp.user_id,
        qp.creationdate,
        qp.viewcount,
        qp.score,
        sum(case when vt.votetypeid = 2 then 1 when vt.votetypeid = 3 then -1 else 0 end) as net_votes,
        count(*) filter (where vt.votetypeid = 5) as favorites,
        dense_rank() over (order by coalesce(qp.viewcount,0) desc, coalesce(qp.score,0) desc, qp.creationdate desc) as hot_rank
    from question_posts qp
    left join votes vt
      on vt.postid = qp.post_id
    group by qp.post_id, qp.user_id, qp.creationdate, qp.viewcount, qp.score
),
dup_clusters as (
    select
        pl.relatedpostid as canonical_qid,
        count(*) filter (where pl.linktypeid = 3) as dup_count,
        count(*) filter (where pl.linktypeid = 1) as link_count
    from postlinks pl
    group by pl.relatedpostid
),
recent_edits as (
    select
        ph.postid,
        max(ph.creationdate) as last_edit_date,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_count,
        count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20)) as mod_action_count
    from posthistory ph
    group by ph.postid
),
badge_rollup as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges
    from badges b
    group by b.userid
),
comment_stats as (
    select
        c.postid,
        count(*) as comments,
        avg(coalesce(nullif(c.score,0), null)) as avg_nonzero_comment_score,
        max(c.creationdate) as last_comment_at
    from comments c
    group by c.postid
),
question_quality as (
    select
        qp.post_id,
        (coalesce(qp.score,0) * 2 + coalesce(qp.viewcount,0) / 100 + coalesce(qp.answercount,0) * 5 + coalesce(hq.net_votes,0) * 3 + coalesce(hq.favorites,0) * 4) 
        - (case when qp.closeddate is not null then 50 else 0 end)
        + (case when qp.acceptedanswerid is not null then 20 else 0 end)
        + (case when re.edit_count > 5 then 5 else 0 end)
        + (case when re.mod_action_count > 0 then -10 else 0 end)
        as quality_score
    from question_posts qp
    left join hot_questions hq on hq.post_id = qp.post_id
    left join recent_edits re on re.postid = qp.post_id
),
user_activity as (
    select
        u.id as user_id,
        count(distinct qp.post_id) as questions_asked,
        count(distinct ap.answer_id) as answers_posted,
        coalesce(sum(qp.viewcount),0) as total_views_on_questions,
        coalesce(sum(case when qp.acceptedanswerid is not null then 1 else 0 end),0) as questions_with_accepted,
        coalesce(avg(nullif(qp.score,0)), null) as avg_nonzero_q_score,
        max(qp.creationdate) as last_question_at,
        max(ap.answer_creation) as last_answer_at
    from users u
    left join question_posts qp on qp.user_id = u.id
    left join answer_posts ap on ap.user_id = u.id
    group by u.id
),
tag_popularity as (
    select
        te.tag,
        count(distinct te.post_id) as question_count,
        sum(qq.quality_score) as total_quality,
        avg(qq.quality_score) as avg_quality,
        percentile_cont(0.9) within group (order by qq.quality_score) as p90_quality
    from tag_expansion te
    join question_quality qq on qq.post_id = te.post_id
    group by te.tag
),
user_top_tags as (
    select
        te_user.user_id,
        te_user.tag,
        row_number() over (partition by te_user.user_id order by count(*) desc, min(qp.creationdate) asc) as rn
    from question_posts qp
    join tag_expansion te_user on te_user.post_id = qp.post_id
    group by te_user.user_id, te_user.tag
),
accepted_answer_times as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        a.id as answer_id,
        a.owneruserid as answerer_id,
        a.creationdate as answer_created,
        q.creationdate as question_created,
        extract(epoch from (a.creationdate - q.creationdate)) as seconds_to_first_answer
    from posts q
    join posts a on a.parentid = q.id
    where q.posttypeid = 1
      and a.posttypeid = 2
),
fast_accept_stats as (
    select
        at.asker_id,
        avg(at.seconds_to_first_answer) filter (where at.seconds_to_first_answer is not null) as avg_secs_to_first_answer,
        min(at.seconds_to_first_answer) as min_secs_to_first_answer,
        max(at.seconds_to_first_answer) as max_secs_to_first_answer,
        count(*) as answers_considered
    from accepted_answer_times at
    group by at.asker_id
),
user_score_rank as (
    select
        u.id as user_id,
        coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end),0) as net_votes_on_posts,
        rank() over (order by coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end),0) desc) as vote_rank
    from users u
    left join posts p on p.owneruserid = u.id
    left join votes v on v.postid = p.id
    group by u.id
),
closed_reason_breakdown as (
    select
        ph.postid,
        max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) else null end) as last_close_reason_id,
        count(*) filter (where ph.posthistorytypeid = 10) as close_votes,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_votes
    from posthistory ph
    group by ph.postid
),
final_user as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.rep_decile,
        ua.questions_asked,
        ua.answers_posted,
        ua.total_views_on_questions,
        ua.questions_with_accepted,
        ua.avg_nonzero_q_score,
        ua.last_question_at,
        ua.last_answer_at,
        uf.first_question_date,
        uf.first_answer_date,
        coalesce(br.gold_badges,0) as gold_badges,
        coalesce(br.silver_badges,0) as silver_badges,
        coalesce(br.bronze_badges,0) as bronze_badges,
        coalesce(br.tag_badges,0) as tag_badges,
        uts.tag as top_tag
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_firsts uf on uf.user_id = ru.user_id
    left join badge_rollup br on br.userid = ru.user_id
    left join user_top_tags uts on uts.user_id = ru.user_id and uts.rn = 1
),
question_rollup as (
    select
        qp.post_id,
        qp.user_id,
        qp.creationdate,
        qp.viewcount,
        qp.score,
        qq.quality_score,
        hq.hot_rank,
        coalesce(cs.comments,0) as comments,
        cs.avg_nonzero_comment_score,
        cs.last_comment_at,
        re.last_edit_date,
        re.edit_count,
        re.mod_action_count,
        coalesce(dc.dup_count,0) as dup_count,
        coalesce(dc.link_count,0) as link_count,
        crb.last_close_reason_id,
        case 
            when crb.last_close_reason_id between 100 and 199 then 'current_close'
            when crb.last_close_reason_id between 1 and 99 then 'legacy_close'
            else 'open_or_unknown'
        end as close_bucket
    from question_posts qp
    left join question_quality qq on qq.post_id = qp.post_id
    left join hot_questions hq on hq.post_id = qp.post_id
    left join comment_stats cs on cs.postid = qp.post_id
    left join recent_edits re on re.postid = qp.post_id
    left join dup_clusters dc on dc.canonical_qid = qp.post_id
    left join closed_reason_breakdown crb on crb.postid = qp.post_id
),
user_question_agg as (
    select
        qr.user_id,
        count(*) as q_count,
        avg(qr.quality_score) as avg_q_quality,
        sum(case when qr.close_bucket = 'open_or_unknown' then 1 else 0 end) as openish,
        sum(case when qr.close_bucket like '%close%' then 1 else 0 end) as closedish,
        sum(qr.dup_count) as total_dups,
        sum(qr.link_count) as total_links,
        max(qr.creationdate) as last_q_at,
        percentile_cont(0.5) within group (order by qr.quality_score) as p50_quality,
        percentile_cont(0.9) within group (order by qr.quality_score) as p90_quality
    from question_rollup qr
    group by qr.user_id
),
final as (
    select
        fu.user_id,
        fu.displayname,
        fu.reputation,
        fu.rep_decile,
        fu.gold_badges,
        fu.silver_badges,
        fu.bronze_badges,
        fu.tag_badges,
        fu.first_question_date,
        fu.first_answer_date,
        fu.last_question_at,
        fu.last_answer_at,
        fu.top_tag,
        uqa.q_count,
        uqa.avg_q_quality,
        uqa.openish,
        uqa.closedish,
        uqa.total_dups,
        uqa.total_links,
        up.net_votes_on_posts,
        up.vote_rank,
        fas.avg_secs_to_first_answer,
        fas.min_secs_to_first_answer,
        fas.max_secs_to_first_answer,
        tp.avg_quality as top_tag_avg_quality,
        tp.p90_quality as top_tag_p90_quality
    from final_user fu
    left join user_question_agg uqa on uqa.user_id = fu.user_id
    left join user_score_rank up on up.user_id = fu.user_id
    left join fast_accept_stats fas on fas.asker_id = fu.user_id
    left join tag_popularity tp on tp.tag = fu.top_tag
)
select *
from final
where coalesce(q_count,0) + coalesce(answers_posted,0) > 0
  and (reputation > 0 or net_votes_on_posts <> 0 or avg_q_quality is not null)
order by
    rep_decile asc nulls last,
    coalesce(avg_q_quality, -1e9) desc,
    vote_rank asc nulls last,
    user_id asc
limit 250;