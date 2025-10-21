-- {"query": "38084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2419} 
with recent_users as (
    select u.id as user_id, u.creationdate
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
power_users as (
    select u.id as user_id
    from users u
    where u.reputation >= (
        select percentile_disc(0.95) within group (order by reputation) from users
    )
),
q as (
    select p.id, p.creationdate, p.owneruserid, p.score, p.viewcount, p.answercount, p.tags
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select max(creationdate) - interval '730 days' from posts)
),
a as (
    select p.id, p.parentid, p.owneruserid, p.score, p.creationdate
    from posts p
    where p.posttypeid = 2
),
accepted as (
    select q.id as question_id, q.acceptedanswerid
    from posts q
    where q.posttypeid = 1 and q.acceptedanswerid is not null
),
hot_history as (
    select ph.postid, min(ph.creationdate) as first_hot_date, count(*) as hot_events
    from posthistory ph
    where ph.posthistorytypeid in (52) -- SelectedHotQuestion
    group by ph.postid
),
dup_clusters as (
    select pl.relatedpostid as canonical_id, count(*) as dup_count
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.relatedpostid
),
tag_expansion as (
    select q.id as question_id, unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
    from q
    where q.tags is not null and q.tags like '<%>'
),
top_tags as (
    select te.tag, count(*) as tag_q_count
    from tag_expansion te
    group by te.tag
    having count(*) >= 50
),
question_engagement as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.creationdate as question_date,
        q.score as q_score,
        q.viewcount as q_views,
        q.answercount as q_answercount,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        count(distinct c.id) as comment_count,
        count(distinct a.id) filter (where a.creationdate <= q.creationdate + interval '7 days') as answers_7d,
        count(distinct a.id) filter (where a.creationdate <= q.creationdate + interval '30 days') as answers_30d,
        min(a.creationdate) as first_answer_date,
        min(a.creationdate) filter (where a.owneruserid = q.owneruserid) as self_answer_date
    from q
    left join votes v on v.postid = q.id and v.creationdate <= q.creationdate + interval '30 days'
    left join comments c on c.postid = q.id and c.creationdate <= q.creationdate + interval '30 days'
    left join a on a.parentid = q.id
    group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.answercount
),
answerer_stats as (
    select
        a.parentid as question_id,
        count(distinct a.owneruserid) as unique_answerers,
        avg(a.score) as avg_answer_score,
        sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
        sum(case when a.score < 0 then 1 else 0 end) as negative_answers
    from a
    group by a.parentid
),
accepted_info as (
    select
        ac.question_id,
        ac.acceptedanswerid,
        aa.owneruserid as accepted_ownerid,
        aa.score as accepted_score,
        aa.creationdate as accepted_date
    from accepted ac
    left join posts aa on aa.id = ac.acceptedanswerid
),
badge_surge as (
    select
        b.userid,
        date_trunc('month', b.date) as month,
        count(*) as badges_in_month
    from badges b
    group by b.userid, date_trunc('month', b.date)
),
asker_badge_momentum as (
    select
        bu.userid,
        avg(bu.badges_in_month) filter (where bu.month >= now() - interval '24 months') as avg_badges_24m,
        max(bu.badges_in_month) filter (where bu.month >= now() - interval '6 months') as max_badges_6m
    from badge_surge bu
    group by bu.userid
),
question_quality as (
    select
        qe.question_id,
        qe.asker_id,
        qe.question_date,
        qe.q_score,
        qe.q_views,
        qe.q_answercount,
        qe.upvotes,
        qe.downvotes,
        qe.favorites,
        qe.comment_count,
        qe.answers_7d,
        qe.answers_30d,
        qe.first_answer_date,
        qe.self_answer_date,
        ai.acceptedanswerid,
        ai.accepted_ownerid,
        ai.accepted_score,
        ai.accepted_date,
        asr.unique_answerers,
        asr.avg_answer_score,
        asr.positive_answers,
        asr.negative_answers,
        hh.first_hot_date,
        hh.hot_events,
        dc.dup_count,
        case when pu.user_id is not null then 1 else 0 end as asker_is_power,
        case when ru.user_id is not null then 1 else 0 end as asker_is_recent,
        abm.avg_badges_24m,
        abm.max_badges_6m
    from question_engagement qe
    left join accepted_info ai on ai.question_id = qe.question_id
    left join answerer_stats asr on asr.question_id = qe.question_id
    left join hot_history hh on hh.postid = qe.question_id
    left join dup_clusters dc on dc.canonical_id = qe.question_id
    left join power_users pu on pu.user_id = qe.asker_id
    left join recent_users ru on ru.user_id = qe.asker_id
    left join asker_badge_momentum abm on abm.userid = qe.asker_id
),
tag_rollup as (
    select
        te.question_id,
        array_agg(te.tag order by tt.tag_q_count desc) as tags_by_popularity,
        sum(case when tt.tag is not null then 1 else 0 end) as popular_tag_hits
    from tag_expansion te
    left join top_tags tt on tt.tag = te.tag
    group by te.question_id
),
early_commenters as (
    select
        c.postid as question_id,
        count(distinct c.userid) filter (where c.creationdate <= p.creationdate + interval '1 day') as commenters_1d,
        count(distinct c.userid) filter (where c.creationdate <= p.creationdate + interval '7 days') as commenters_7d
    from comments c
    join posts p on p.id = c.postid and p.posttypeid = 1
    group by c.postid, p.creationdate
),
question_flags as (
    select
        ph.postid as question_id,
        sum(case when ph.posthistorytypeid in (10,12,14,19,35) then 1 else 0 end) as mod_events,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (10)) as closed_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (11)) as reopened_at
    from posthistory ph
    group by ph.postid
),
final as (
    select
        qq.question_id,
        qq.asker_id,
        qq.question_date,
        qq.q_score,
        qq.q_views,
        qq.q_answercount,
        qq.upvotes,
        qq.downvotes,
        qq.favorites,
        qq.comment_count,
        qq.answers_7d,
        qq.answers_30d,
        qq.first_answer_date,
        qq.self_answer_date,
        qq.acceptedanswerid,
        qq.accepted_ownerid,
        qq.accepted_score,
        qq.accepted_date,
        qq.unique_answerers,
        qq.avg_answer_score,
        qq.positive_answers,
        qq.negative_answers,
        qq.first_hot_date,
        qq.hot_events,
        coalesce(qq.dup_count, 0) as dup_count,
        qq.asker_is_power,
        qq.asker_is_recent,
        coalesce(qq.avg_badges_24m, 0) as avg_badges_24m,
        coalesce(qq.max_badges_6m, 0) as max_badges_6m,
        tr.tags_by_popularity,
        coalesce(tr.popular_tag_hits, 0) as popular_tag_hits,
        coalesce(ec.commenters_1d, 0) as commenters_1d,
        coalesce(ec.commenters_7d, 0) as commenters_7d,
        coalesce(qf.mod_events, 0) as mod_events,
        qf.closed_at,
        qf.reopened_at
    from question_quality qq
    left join tag_rollup tr on tr.question_id = qq.question_id
    left join early_commenters ec on ec.question_id = qq.question_id
    left join question_flags qf on qf.question_id = qq.question_id
)
select
    f.question_id,
    p.title,
    p.owneruserid as asker_id,
    u.displayname as asker_name,
    f.q_score,
    f.q_views,
    f.upvotes,
    f.downvotes,
    f.favorites,
    f.unique_answerers,
    f.answers_7d,
    f.answers_30d,
    f.accepted_score,
    extract(epoch from coalesce(f.accepted_date, now()) - f.question_date) / 3600.0 as hours_to_accept_or_now,
    f.hot_events,
    f.dup_count,
    f.asker_is_power,
    f.asker_is_recent,
    f.avg_badges_24m,
    f.max_badges_6m,
    f.popular_tag_hits,
    f.commenters_1d,
    f.commenters_7d,
    f.mod_events,
    f.closed_at,
    f.reopened_at,
    f.tags_by_popularity
from final f
join posts p on p.id = f.question_id
left join users u on u.id = p.owneruserid
where f.q_views >= (
        select percentile_disc(0.90) within group (order by coalesce(viewcount,0))
        from posts
        where posttypeid = 1
    )
  and coalesce(f.accepted_score, 0) >= (
        select percentile_disc(0.50) within group (order by coalesce(score,0))
        from posts where posttypeid = 2
    )
  and f.answers_7d >= 1
order by f.q_score desc nulls last, f.q_views desc
limit 500;