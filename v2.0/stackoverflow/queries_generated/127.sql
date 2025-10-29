-- {"query": "127.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4052} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), '(none)') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month,
        dense_rank() over (order by date_trunc('month', u.creationdate)) as cohort_rank
    from users u
    where u.creationdate >= (select coalesce(max(creationdate), timestamp '1970-01-01') - interval '5 years' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score, 0)) as total_post_score,
        sum(coalesce(p.viewcount, 0)) as total_views,
        max(p.lastactivitydate) as last_post_activity,
        avg(nullif(p.answercount, 0)) as avg_answers_per_question
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
tag_exploded as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        lower(trim(tg)) as tag_name
    from posts p
    cross join lateral unnest(string_to_array(substring(p.tags from 2 for length(p.tags)-2), '><')) as tg
    where p.posttypeid = 1
      and p.tags is not null
),
user_top_tags as (
    select
        te.user_id,
        te.tag_name,
        count(*) as tag_use_count,
        row_number() over (partition by te.user_id order by count(*) desc, te.tag_name) as rn
    from tag_exploded te
    group by te.user_id, te.tag_name
),
badge_rollup as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        sum(case when b.class = 1 then 1 else 0 end) as gold_count,
        sum(case when b.class = 2 then 1 else 0 end) as silver_count,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
vote_summaries as (
    select
        p.owneruserid as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from posts p
    left join votes v on v.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
comment_activity as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        sum(coalesce(c.score,0)) as comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
question_closures as (
    select
        ph.postid,
        min(ph.creationdate) as first_closed_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_id_raw
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
duplicates as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        min(pl.creationdate) as dup_marked_at
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
question_meta as (
    select
        q.id as post_id,
        q.owneruserid as user_id,
        q.acceptedanswerid,
        q.creationdate,
        q.score,
        q.viewcount,
        q.answercount,
        q.title,
        q.tags,
        qc.first_closed_at,
        qc.last_reopened_at,
        qc.close_events,
        qc.reopen_events,
        d.dup_marked_at,
        case
            when qc.first_closed_at is not null and (qc.last_reopened_at is null or qc.first_closed_at > qc.last_reopened_at) then 1
            else 0
        end as is_currently_closed
    from posts q
    left join question_closures qc on qc.postid = q.id
    left join duplicates d on d.dup_post_id = q.id
    where q.posttypeid = 1
),
answer_meta as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as user_id,
        a.creationdate,
        a.score,
        a.commentcount,
        row_number() over (partition by a.parentid order by a.score desc, a.creationdate asc) as rn_by_score
    from posts a
    where a.posttypeid = 2
),
accepted_answerers as (
    select
        am.user_id,
        count(*) as accepted_answers_authored,
        avg(am.score) as avg_accepted_answer_score
    from answer_meta am
    join posts q on q.id = am.question_id and q.acceptedanswerid = am.answer_id
    group by am.user_id
),
user_quality as (
    select
        ua.user_id,
        coalesce(ua.a_count,0) as answers,
        coalesce(ua.q_count,0) as questions,
        coalesce(vs.upvotes_received,0) as up_rcv,
        coalesce(vs.downvotes_received,0) as down_rcv,
        coalesce(aa.accepted_answers_authored,0) as acc_cnt,
        coalesce(ua.total_post_score,0) as post_score,
        coalesce(ua.total_views,0) as views
    from user_activity ua
    left join vote_summaries vs on vs.user_id = ua.user_id
    left join accepted_answerers aa on aa.user_id = ua.user_id
),
score_buckets as (
    select
        uq.user_id,
        ntile(10) over (order by nullif(uq.post_score,0)) as post_score_decile,
        ntile(10) over (order by nullif(uq.views,0)) as view_decile,
        case
            when uq.answers >= 100 then '100+'
            when uq.answers >= 50 then '50-99'
            when uq.answers >= 20 then '20-49'
            when uq.answers >= 5 then '5-19'
            when uq.answers >= 1 then '1-4'
            else '0'
        end as answer_bucket,
        case when (uq.down_rcv + uq.up_rcv) > 0 then round(uq.up_rcv::numeric / nullif(uq.down_rcv + uq.up_rcv,0), 4) else null end as upvote_ratio
    from user_quality uq
),
recent_posts as (
    select
        p.id,
        p.owneruserid as user_id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.commentcount
    from posts p
    where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
user_recent_engagement as (
    select
        rp.user_id,
        count(*) as recent_posts_count,
        sum(case when rp.posttypeid = 1 then 1 else 0 end) as recent_q,
        sum(case when rp.posttypeid = 2 then 1 else 0 end) as recent_a,
        avg(rp.score) as recent_avg_score,
        avg(rp.viewcount) as recent_avg_views,
        sum(rp.commentcount) as recent_comments
    from recent_posts rp
    where rp.user_id is not null
    group by rp.user_id
),
-- correlated subquery for user's latest hotness spike (high delta score per hour on any post)
latest_hot_spike as (
    select
        p.owneruserid as user_id,
        max(
            (
                select max(coalesce(p2.score,0) - coalesce(p1.score,0))::numeric
                from posts p1
                join posts p2 on p2.id = p1.id and p2.lastactivitydate >= p1.creationdate
                where p1.owneruserid = p.owneruserid
            )
        ) as spike_score
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
-- derive per-user text signals from AboutMe and Titles (string expressions, null logic)
text_signals as (
    select
        u.id as user_id,
        length(coalesce(u.aboutme, '')) as about_len,
        sum(length(coalesce(q.title,''))) as title_char_sum,
        count(q.id) filter (where position('how to' in lower(coalesce(q.title,''))) > 0) as howto_titles,
        count(q.id) filter (where lower(coalesce(q.title,'')) similar to '%(why|what|when|where|who|how)%') as wh_titles
    from users u
    left join posts q on q.owneruserid = u.id and q.posttypeid = 1
    group by u.id, length(coalesce(u.aboutme, ''))
),
-- assemble final user panel with rich features
user_panel as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.websiteurl,
        ru.cohort_month,
        ru.cohort_rank,
        coalesce(ua.q_count,0) as total_questions,
        coalesce(ua.a_count,0) as total_answers,
        coalesce(ua.total_post_score,0) as total_post_score,
        coalesce(ua.total_views,0) as total_views,
        ua.last_post_activity,
        coalesce(ua.avg_answers_per_question, 0) as avg_answers_per_question,
        coalesce(vs.upvotes_received,0) as upvotes_received,
        coalesce(vs.downvotes_received,0) as downvotes_received,
        coalesce(vs.bounty_started,0) as bounty_started,
        coalesce(vs.bounty_awarded,0) as bounty_awarded,
        coalesce(ca.comment_count,0) as comment_count,
        coalesce(ca.comment_score,0) as comment_score,
        ca.last_comment_date,
        coalesce(br.badge_count,0) as badge_count,
        coalesce(br.gold_count,0) as gold_badges,
        coalesce(br.silver_count,0) as silver_badges,
        coalesce(br.bronze_count,0) as bronze_badges,
        br.first_badge_date,
        br.last_badge_date,
        utt.tag_name as top_tag_1,
        utt.tag_use_count as top_tag_1_count,
        coalesce(aa.accepted_answers_authored,0) as accepted_answers_authored,
        coalesce(aa.avg_accepted_answer_score,0) as avg_accepted_answer_score,
        sb.post_score_decile,
        sb.view_decile,
        sb.answer_bucket,
        sb.upvote_ratio,
        ure.recent_posts_count,
        ure.recent_q,
        ure.recent_a,
        ure.recent_avg_score,
        ure.recent_avg_views,
        ure.recent_comments,
        ts.about_len,
        ts.title_char_sum,
        ts.howto_titles,
        ts.wh_titles,
        lhs.spike_score
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join vote_summaries vs on vs.user_id = ru.user_id
    left join comment_activity ca on ca.user_id = ru.user_id
    left join badge_rollup br on br.user_id = ru.user_id
    left join user_top_tags utt on utt.user_id = ru.user_id and utt.rn = 1
    left join accepted_answerers aa on aa.user_id = ru.user_id
    left join score_buckets sb on sb.user_id = ru.user_id
    left join user_recent_engagement ure on ure.user_id = ru.user_id
    left join text_signals ts on ts.user_id = ru.user_id
    left join latest_hot_spike lhs on lhs.user_id = ru.user_id
),
-- build question-level aggregates connected to user
question_panel as (
    select
        qm.user_id,
        count(*) as total_q,
        count(*) filter (where qm.is_currently_closed = 1) as closed_now_q,
        count(*) filter (where qm.dup_marked_at is not null) as duplicate_q,
        avg(qm.score) as avg_q_score,
        avg(qm.viewcount) as avg_q_views,
        sum(qm.answercount) as sum_answers_on_q,
        count(qm.acceptedanswerid) as q_with_accepted,
        max(qm.creationdate) as last_q_created
    from question_meta qm
    group by qm.user_id
),
-- answer-level aggregates
answer_panel as (
    select
        am.user_id,
        count(*) as total_a,
        avg(am.score) as avg_a_score,
        count(*) filter (where am.rn_by_score = 1) as top_answers_count,
        max(am.creationdate) as last_a_created
    from answer_meta am
    group by am.user_id
),
-- combine panels with left/full outer join permutations for stress
combined as (
    select
        up.*,
        qp.total_q,
        qp.closed_now_q,
        qp.duplicate_q,
        qp.avg_q_score,
        qp.avg_q_views,
        qp.sum_answers_on_q,
        qp.q_with_accepted,
        qp.last_q_created,
        ap.total_a,
        ap.avg_a_score,
        ap.top_answers_count,
        ap.last_a_created
    from user_panel up
    full outer join question_panel qp on qp.user_id = up.user_id
    left join answer_panel ap on coalesce(up.user_id, qp.user_id) = ap.user_id
),
-- derive a composite score using varied expressions and null handling
scored as (
    select
        c.*,
        coalesce(c.reputation,0)
        + coalesce(c.total_post_score,0) * 0.5
        + coalesce(c.upvotes_received,0) * 1.2
        - coalesce(c.downvotes_received,0) * 0.8
        + coalesce(c.badge_count,0) * 2
        + coalesce(c.accepted_answers_authored,0) * 5
        + coalesce(c.top_answers_count,0) * 3
        + case when coalesce(c.upvote_ratio,0) >= 0.8 then 10 when c.upvote_ratio is null then 0 else -5 end
        + case when coalesce(c.closed_now_q,0) > 10 then -15 else 0 end
        + case when coalesce(c.duplicate_q,0) > 5 then -5 else 0 end
        + least(coalesce(c.recent_avg_score,0) * 2, 30)
        + least(coalesce(c.recent_posts_count,0), 20)
        + coalesce(c.spike_score,0)
        as composite_score
    from combined c
),
-- last: select with complex predicates, set operators, and ordering
final_users as (
    select * from scored
    where
        -- complicated predicate: mix of nulls, pattern search, and numeric ranges
        (
            (displayname is not null and length(displayname) >= 3)
            or (websiteurl ilike '%github%' and coalesce(badge_count,0) >= 1)
        )
        and coalesce(total_q,0) + coalesce(total_a,0) >= 5
        and (
            composite_score > percentile_cont(0.75) within group (order by composite_score)
            or (upvote_ratio is not null and upvote_ratio >= 0.85 and coalesce(total_a,0) >= 10)
        )
),
runner_union as (
    select user_id, displayname, composite_score, cohort_rank, 'A' as lane from final_users
    union all
    select user_id, displayname, composite_score, cohort_rank, 'B' as lane from final_users where (cohort_rank % 2) = 0
    union
    select user_id, displayname, composite_score, cohort_rank, 'C' as lane from final_users where (cohort_rank % 3) = 0
)
select
    ru.user_id,
    max(ru.displayname) as displayname,
    round(avg(ru.composite_score)::numeric, 3) as avg_composite_score,
    min(ru.cohort_rank) as min_cohort_rank,
    string_agg(distinct ru.lane, '' order by ru.lane) as lanes,
    count(*) as appearances,
    max(s.total_q) as total_q,
    max(s.total_a) as total_a,
    max(s.badge_count) as badge_count,
    max(s.top_tag_1) as top_tag,
    max(s.answer_bucket) as answer_bucket,
    max(s.upvote_ratio) as upvote_ratio,
    max(s.recent_posts_count) as recent_posts,
    max(s.closed_now_q) as closed_now_q
from runner_union ru
join scored s on s.user_id = ru.user_id
left join posts p on p.owneruserid = ru.user_id and p.posttypeid in (1,2) and p.creationdate >= s.cohort_month
left join postlinks pl on pl.postid = p.id and pl.linktypeid in (1,3)
left join votes v on v.postid = p.id and v.votetypeid in (2,3,8,9)
group by ru.user_id
having
    count(*) >= 1
    and sum(case when p.id is null then 1 else 0 end) >= 0
order by avg_composite_score desc nulls last, min_cohort_rank asc, ru.user_id asc
limit 250;