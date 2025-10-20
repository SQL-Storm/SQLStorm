-- {"query": "8076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3145} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.websiteurl,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= now() - interval '5 years'
),
user_badge_summary as (
    select
        b.userid,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_count,
        count(*) filter (where b.class = 2) as silver_count,
        count(*) filter (where b.class = 3) as bronze_count,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
q as (
    select
        p.id as question_id,
        p.owneruserid as asker_id,
        p.score as q_score,
        p.viewcount,
        p.favoritecount,
        p.answercount,
        p.creationdate as q_created,
        p.closeddate,
        p.acceptedanswerid,
        p.tags,
        p.title,
        date_trunc('month', p.creationdate) as q_month
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= now() - interval '5 years'
),
a as (
    select
        p.id as answer_id,
        p.parentid as question_id,
        p.owneruserid as answerer_id,
        p.score as a_score,
        p.creationdate as a_created
    from posts p
    where p.posttypeid = 2
),
first_answers as (
    select
        a.question_id,
        a.answer_id,
        a.answerer_id,
        a.a_score,
        a.a_created,
        row_number() over (partition by a.question_id order by a.a_created asc, a.answer_id asc) as rn
    from a
),
answer_latency as (
    select
        q.question_id,
        q.asker_id,
        q.q_created,
        fa.answer_id,
        fa.answerer_id,
        fa.a_created,
        extract(epoch from (fa.a_created - q.q_created))/60.0 as minutes_to_first_answer
    from q
    join first_answers fa on fa.question_id = q.question_id and fa.rn = 1
),
accepted_answerers as (
    select
        q.question_id,
        q.acceptedanswerid,
        a.answerer_id as accepted_answerer_id
    from q
    left join a on a.answer_id = q.acceptedanswerid
),
post_votes as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 5) as favorites,
        count(*) filter (where v.votetypeid = 8) as bounties_started,
        count(*) filter (where v.votetypeid = 9) as bounties_closed,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as total_bounty_amount
    from votes v
    group by v.postid
),
close_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_closed_at,
        max(ph.creationdate) as last_closed_at,
        count(*) as close_event_ct,
        min(nullif(ph.comment, ''))::int as close_reason_id_min
    from posthistory ph
    where ph.posthistorytypeid = 10
    group by ph.postid
),
reopen_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_reopened_at,
        count(*) as reopen_event_ct
    from posthistory ph
    where ph.posthistorytypeid = 11
    group by ph.postid
),
duplicates as (
    select
        pl.postid as question_id,
        count(*) filter (where pl.linktypeid = 3) as dup_links_ct,
        count(*) filter (where pl.linktypeid = 1) as linked_ct,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
tag_explode as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag
    from q
),
tag_rank as (
    select
        t.question_id,
        t.tag,
        row_number() over (partition by t.question_id order by coalesce(ta.count,0) desc, t.tag) as tag_rank_by_popularity
    from tag_explode t
    left join tags ta on ta.tagname = t.tag
),
question_activity as (
    select
        q.question_id,
        q.asker_id,
        q.q_created,
        q.q_score,
        q.viewcount,
        q.favoritecount,
        q.answercount,
        q.closeddate,
        q.acceptedanswerid,
        q.tags,
        q.title,
        q.q_month,
        pv.upvotes,
        pv.downvotes,
        pv.favorites,
        pv.bounties_started,
        pv.bounties_closed,
        pv.total_bounty_amount,
        ce.first_closed_at,
        ce.last_closed_at,
        ce.close_event_ct,
        ce.close_reason_id_min,
        re.first_reopened_at,
        re.reopen_event_ct,
        du.dup_links_ct,
        du.linked_ct,
        du.last_link_date
    from q
    left join post_votes pv on pv.postid = q.question_id
    left join close_events ce on ce.postid = q.question_id
    left join reopen_events re on re.postid = q.question_id
    left join duplicates du on du.question_id = q.question_id
),
asker_stats as (
    select
        qa.question_id,
        u.id as user_id,
        u.displayname as user_name,
        u.reputation,
        u.creationdate as user_created,
        u.location,
        u.websiteurl,
        ub.badge_count,
        ub.gold_count,
        ub.silver_count,
        ub.bronze_count,
        ub.last_badge_date,
        ru.cohort_month as user_cohort
    from question_activity qa
    left join users u on u.id = qa.asker_id
    left join user_badge_summary ub on ub.userid = u.id
    left join recent_users ru on ru.user_id = u.id
),
answerer_stats as (
    select
        al.question_id,
        ua.id as user_id,
        ua.displayname as user_name,
        ua.reputation,
        ub.badge_count,
        al.minutes_to_first_answer,
        case
            when aa.accepted_answerer_id = ua.id then 1
            else 0
        end as is_accepted_answerer
    from answer_latency al
    left join accepted_answerers aa on aa.question_id = al.question_id
    left join users ua on ua.id = al.answerer_id
    left join user_badge_summary ub on ub.userid = ua.id
),
question_quality_score as (
    select
        qa.question_id,
        qa.q_month,
        qa.q_score,
        qa.viewcount,
        qa.favoritecount,
        qa.answercount,
        coalesce(qa.upvotes,0) as upvotes,
        coalesce(qa.downvotes,0) as downvotes,
        coalesce(qa.favorites,0) as vote_favorites,
        coalesce(qa.total_bounty_amount,0) as total_bounty_amount,
        coalesce(qa.dup_links_ct,0) as dup_links_ct,
        coalesce(qa.linked_ct,0) as linked_ct,
        coalesce(a.minutes_to_first_answer, 60*24*30) as minutes_to_first_answer_capped,
        coalesce(avg(a.minutes_to_first_answer) over (partition by qa.q_month), 60*24*30) as cohort_avg_minutes_to_first_answer,
        case
            when qa.closeddate is not null then 1 else 0
        end as was_closed,
        case
            when qa.first_closed_at is not null and qa.first_reopened_at is not null and qa.first_reopened_at > qa.first_closed_at then 1 else 0
        end as was_reopened,
        case
            when qa.acceptedanswerid is not null then 1 else 0
        end as has_accepted_answer,
        case
            when qa.viewcount is null or qa.viewcount = 0 then null
            else (qa.q_score::numeric / nullif(qa.viewcount,0))::numeric
        end as score_per_view,
        sum(case when tr.tag_rank_by_popularity = 1 then 1 else 0 end) over (partition by qa.question_id) as has_top_tag
    from question_activity qa
    left join answer_latency a on a.question_id = qa.question_id
    left join tag_rank tr on tr.question_id = qa.question_id
),
cohort_agg as (
    select
        qq.q_month,
        count(*) as questions_in_cohort,
        avg(qq.q_score) as avg_q_score,
        avg(qq.viewcount) as avg_views,
        avg(qq.favoritecount) as avg_favs,
        avg(qq.answercount) as avg_answers,
        avg(qq.upvotes - qq.downvotes) as avg_net_votes,
        avg(qq.minutes_to_first_answer_capped) as avg_minutes_to_first_answer,
        avg(case when qq.was_closed = 1 then 1 else 0 end)::numeric as pct_closed,
        avg(case when qq.was_reopened = 1 then 1 else 0 end)::numeric as pct_reopened,
        avg(case when qq.has_accepted_answer = 1 then 1 else 0 end)::numeric as pct_with_accepted
    from question_quality_score qq
    group by qq.q_month
),
scored as (
    select
        qq.question_id,
        qq.q_month,
        qq.q_score,
        qq.viewcount,
        qq.favoritecount,
        qq.answercount,
        qq.upvotes,
        qq.downvotes,
        qq.vote_favorites,
        qq.total_bounty_amount,
        qq.dup_links_ct,
        qq.linked_ct,
        qq.minutes_to_first_answer_capped,
        qq.cohort_avg_minutes_to_first_answer,
        qq.was_closed,
        qq.was_reopened,
        qq.has_accepted_answer,
        qq.score_per_view,
        qq.has_top_tag,
        ca.questions_in_cohort,
        ca.avg_q_score,
        ca.avg_views,
        ca.avg_favs,
        ca.avg_answers,
        ca.avg_net_votes,
        ca.avg_minutes_to_first_answer,
        ca.pct_closed,
        ca.pct_reopened,
        ca.pct_with_accepted,
        (
            coalesce(qq.q_score,0)*1.0
            + coalesce(qq.upvotes - qq.downvotes,0)*0.7
            + coalesce(qq.favoritecount,0)*0.5
            + least(coalesce(qq.viewcount,0), 5000)/5000.0*2.0
            + case when qq.has_accepted_answer = 1 then 2.0 else 0.0 end
            - case when qq.was_closed = 1 then 3.0 else 0.0 end
            - least(coalesce(qq.dup_links_ct,0), 5)*0.8
            + least(coalesce(qq.linked_ct,0), 10)*0.2
            + least(coalesce(qq.total_bounty_amount,0), 500)/500.0
            - greatest(least((qq.minutes_to_first_answer_capped - qq.cohort_avg_minutes_to_first_answer)/60.0, 120), -120)/120.0
            + case when qq.has_top_tag > 0 then 0.3 else 0.0 end
        ) as performance_score
    from question_quality_score qq
    left join cohort_agg ca on ca.q_month = qq.q_month
),
ranked as (
    select
        s.*,
        ntile(10) over (order by s.performance_score desc nulls last) as decile,
        row_number() over (order by s.performance_score desc nulls last) as global_rank,
        row_number() over (partition by s.q_month order by s.performance_score desc nulls last) as cohort_rank
    from scored s
),
topn as (
    select
        r.question_id,
        r.q_month,
        r.performance_score,
        r.global_rank,
        r.cohort_rank,
        r.decile
    from ranked r
    where r.decile in (1,2,3)
       or r.global_rank <= 200
)
select
    t.question_id,
    coalesce(p.title, '[no title]') as title,
    t.performance_score,
    t.global_rank,
    t.cohort_rank,
    t.decile,
    qa.q_score,
    qa.viewcount,
    qa.favoritecount,
    qa.answercount,
    qa.upvotes,
    qa.downvotes,
    qa.total_bounty_amount,
    qa.dup_links_ct,
    qa.linked_ct,
    qa.first_closed_at,
    qa.first_reopened_at,
    al.minutes_to_first_answer,
    ask.user_name as asker_name,
    ask.reputation as asker_rep,
    ask.badge_count as asker_badges,
    ans.user_name as first_answerer_name,
    ans.reputation as first_answerer_rep,
    ans.badge_count as first_answerer_badges,
    ans.is_accepted_answerer,
    substring(coalesce(p.tags,''), 1, 200) as tags_prefix,
    case
        when p.ownerdisplayname is null and p.owneruserid is not null then 'registered'
        when p.ownerdisplayname is not null and p.owneruserid is null then 'unregistered'
        when p.owneruserid is null then 'deleted/unknown'
        else 'registered'
    end as owner_status
from topn t
join question_activity qa on qa.question_id = t.question_id
left join posts p on p.id = t.question_id
left join answer_latency al on al.question_id = t.question_id
left join asker_stats ask on ask.question_id = t.question_id
left join answerer_stats ans on ans.question_id = t.question_id
where coalesce(p.contentlicense, '') not like '%CC-Wiki%' or p.contentlicense is null
order by t.performance_score desc nulls last, qa.q_score desc, t.question_id desc
limit 500;