-- {"query": "965.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3204} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.host') as website_host,
        row_number() over (order by u.creationdate desc, u.id) as rn
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
tagged_questions as (
    select
        p.id as question_id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.tags,
        cardinality(string_to_array(coalesce(substring(p.tags, 2, greatest(length(p.tags)-2,0)), ''), '><')) as tag_count,
        (select count(*) from comments c where c.postid = p.id) as comment_count,
        (select count(*) from votes v where v.postid = p.id and v.votetypeid = 2) as upvotes,
        (select count(*) from votes v where v.postid = p.id and v.votetypeid = 3) as downvotes
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
answers_aug as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.score as answer_score,
        a.creationdate as answer_created,
        lead(a.creationdate) over (partition by a.parentid order by a.creationdate) as next_answer_time,
        lag(a.creationdate) over (partition by a.parentid order by a.creationdate) as prev_answer_time,
        row_number() over (partition by a.parentid order by a.score desc nulls last, a.id) as answer_rank_by_score
    from posts a
    where a.posttypeid = 2
),
q_with_first_answer as (
    select
        tq.question_id,
        min(a.creationdate) as first_answer_time,
        count(*) as total_answers
    from posts a
    join tagged_questions tq on tq.question_id = a.parentid
    where a.posttypeid = 2
    group by tq.question_id
),
dup_links as (
    select pl.postid as duplicate_id, pl.relatedpostid as original_id
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid and lt.name ilike 'Duplicate'
),
user_badge_agg as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(*) as total_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
q_edit_events as (
    select
        ph.postid as question_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_code_raw
    from posthistory ph
    join posts p on p.id = ph.postid and p.posttypeid = 1
    group by ph.postid
),
tag_expansion as (
    select
        tq.question_id,
        unnest(string_to_array(substring(tq.tags, 2, greatest(length(tq.tags)-2,0)), '><')) as tagname
    from tagged_questions tq
    where tq.tags is not null
),
tag_stats as (
    select
        te.question_id,
        count(*) as tags_on_question,
        sum(case when t.count > 1000 then 1 else 0 end) as popular_tag_hits,
        string_agg(te.tagname, ',' order by te.tagname) as tag_list_csv
    from tag_expansion te
    left join tags t on t.tagname = te.tagname
    group by te.question_id
),
vote_agg as (
    select
        p.id as post_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upmods,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downmods,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        min(v.creationdate) filter (where v.votetypeid in (2,3)) as first_vote_time
    from posts p
    left join votes v on v.postid = p.id
    where p.posttypeid in (1,2)
    group by p.id
),
user_activity as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as total_post_score,
        max(p.lastactivitydate) as last_activity
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
question_scored as (
    select
        tq.question_id,
        tq.owneruserid as asker_id,
        tq.creationdate,
        tq.score,
        tq.viewcount,
        tq.tag_count,
        tq.comment_count,
        tq.upvotes,
        tq.downvotes,
        qa.total_answers,
        qa.first_answer_time,
        extract(epoch from (qa.first_answer_time - tq.creationdate)) as sec_to_first_answer,
        coalesce(qa.total_answers,0) as answers_count_coalesce
    from tagged_questions tq
    left join q_with_first_answer qa on qa.question_id = tq.question_id
),
asker_profile as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.website_host,
        ua.q_count,
        ua.a_count,
        ua.total_post_score,
        ub.total_badges,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        greatest(coalesce(ua.last_activity, timestamp 'epoch'), coalesce(ub.last_badge_date, timestamp 'epoch')) as last_seen_signal
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badge_agg ub on ub.userid = ru.user_id
),
closed_or_dup as (
    select
        p.id as question_id,
        case
            when p.closeddate is not null then 1
            when dl.duplicate_id is not null then 1
            else 0
        end as is_closed_or_duplicate,
        coalesce(dl.original_id, null) as original_if_duplicate
    from posts p
    left join dup_links dl on dl.duplicate_id = p.id
    where p.posttypeid = 1
),
ranked_questions as (
    select
        qs.question_id,
        qs.asker_id,
        qs.creationdate,
        qs.score,
        qs.viewcount,
        qs.tag_count,
        qs.comment_count,
        qs.upvotes,
        qs.downvotes,
        qs.total_answers,
        qs.first_answer_time,
        qs.sec_to_first_answer,
        ts.tags_on_question,
        ts.popular_tag_hits,
        ts.tag_list_csv,
        qa.is_closed_or_duplicate,
        qa.original_if_duplicate,
        va.upmods,
        va.downmods,
        va.bounty_started,
        va.bounty_awarded,
        va.first_vote_time,
        dense_rank() over (
            order by
                coalesce(qs.viewcount,0) desc,
                coalesce(qs.score, -2147483648) desc,
                coalesce(qs.total_answers,0) desc,
                qs.creationdate desc
        ) as popularity_rank
    from question_scored qs
    left join tag_stats ts on ts.question_id = qs.question_id
    left join closed_or_dup qa on qa.question_id = qs.question_id
    left join vote_agg va on va.post_id = qs.question_id
),
answer_quality as (
    select
        aa.question_id,
        avg(aa.answer_score) as avg_answer_score,
        max(aa.answer_score) as max_answer_score,
        percentile_disc(0.5) within group (order by aa.answer_score) as median_answer_score,
        avg(extract(epoch from (aa.next_answer_time - aa.answer_created))) as avg_gap_to_next_answer_sec,
        sum(case when aa.answer_rank_by_score = 1 then 1 else 0 end) as has_top_answer
    from answers_aug aa
    group by aa.question_id
),
accepted_vs_top as (
    select
        q.id as question_id,
        case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted,
        case
            when q.acceptedanswerid is null then null
            else (select pa.score from posts pa where pa.id = q.acceptedanswerid)
        end as accepted_score,
        case
            when q.acceptedanswerid is null then null
            else (select row_number() over (order by p2.score desc nulls last, p2.id)
                  from posts p2
                  where p2.parentid = q.id and p2.posttypeid = 2
                  order by p2.score desc nulls last, p2.id
                  limit 1) -- placeholder compute
        end as dummy_rank_calc
    from posts q
    where q.posttypeid = 1
),
final_set as (
    select
        rq.question_id,
        rq.asker_id,
        rq.creationdate,
        rq.score,
        rq.viewcount,
        rq.tag_count,
        rq.comment_count,
        rq.upvotes,
        rq.downvotes,
        rq.total_answers,
        rq.first_answer_time,
        rq.sec_to_first_answer,
        rq.tags_on_question,
        rq.popular_tag_hits,
        rq.tag_list_csv,
        rq.is_closed_or_duplicate,
        rq.original_if_duplicate,
        rq.upmods,
        rq.downmods,
        rq.bounty_started,
        rq.bounty_awarded,
        rq.first_vote_time,
        rq.popularity_rank,
        aq.avg_answer_score,
        aq.max_answer_score,
        aq.median_answer_score,
        aq.avg_gap_to_next_answer_sec,
        av.has_accepted,
        av.accepted_score
    from ranked_questions rq
    left join answer_quality aq on aq.question_id = rq.question_id
    left join accepted_vs_top av on av.question_id = rq.question_id
),
bench_base as (
    select
        fs.*,
        ap.displayname as asker_displayname,
        ap.reputation as asker_reputation,
        ap.website_host,
        ap.q_count as asker_q_count,
        ap.a_count as asker_a_count,
        ap.total_post_score as asker_total_post_score,
        ap.total_badges as asker_total_badges,
        ap.gold_badges,
        ap.silver_badges,
        ap.bronze_badges,
        ap.last_seen_signal,
        case
            when coalesce(fs.viewcount,0) = 0 then null
            else round((coalesce(fs.upvotes,0)::numeric - coalesce(fs.downvotes,0)::numeric) / nullif(fs.viewcount::numeric,0), 6)
        end as net_votes_per_view,
        case
            when fs.sec_to_first_answer is null then null
            when fs.sec_to_first_answer < 0 then null
            else fs.sec_to_first_answer
        end as sane_sec_to_first_answer
    from final_set fs
    left join asker_profile ap on ap.user_id = fs.asker_id
),
top_and_bottom as (
    select * from (
        select bb.*, 'TOP' as bucket
        from bench_base bb
        where bb.popularity_rank <= 50
        union all
        select bb.*, 'BOTTOM' as bucket
        from bench_base bb
        where bb.popularity_rank > (select max(popularity_rank) - 50 from bench_base)
    ) z
),
null_sentinel as (
    select
        t.question_id,
        coalesce(nullif(t.asker_displayname, ''), '(anonymous)') as asker_displayname,
        coalesce(t.website_host, 'unknown.host') as website_host_norm,
        coalesce(t.tag_list_csv, '(no-tags)') as tag_list_csv_norm,
        coalesce(t.avg_answer_score, -9999) as avg_answer_score_sentinel,
        t.*
    from top_and_bottom t
)
select
    ns.bucket,
    ns.popularity_rank,
    ns.question_id,
    ns.asker_id,
    ns.asker_displayname,
    ns.website_host_norm as website_host,
    ns.creationdate,
    ns.score,
    ns.viewcount,
    ns.tag_count,
    ns.comment_count,
    ns.tags_on_question,
    ns.popular_tag_hits,
    ns.tag_list_csv_norm as tag_list_csv,
    ns.total_answers,
    ns.sane_sec_to_first_answer as sec_to_first_answer,
    ns.avg_answer_score_sentinel as avg_answer_score,
    ns.max_answer_score,
    ns.median_answer_score,
    ns.avg_gap_to_next_answer_sec,
    ns.upvotes,
    ns.downvotes,
    ns.net_votes_per_view,
    ns.is_closed_or_duplicate,
    ns.original_if_duplicate,
    ns.upmods,
    ns.downmods,
    ns.bounty_started,
    ns.bounty_awarded,
    ns.first_vote_time,
    ns.asker_reputation,
    ns.asker_q_count,
    ns.asker_a_count,
    ns.asker_total_post_score,
    ns.asker_total_badges,
    ns.gold_badges,
    ns.silver_badges,
    ns.bronze_badges,
    case
        when ns.last_seen_signal is null then 'never'
        when ns.last_seen_signal < now() - interval '365 days' then 'stale'
        else 'active'
    end as asker_activity_bucket
from null_sentinel ns
where
    (
        ns.bucket = 'TOP'
        or (
            ns.bucket = 'BOTTOM'
            and (
                ns.is_closed_or_duplicate = 1
                or ns.popular_tag_hits = 0
                or ns.sec_to_first_answer is null
            )
        )
    )
order by ns.bucket, ns.popularity_rank, ns.question_id;