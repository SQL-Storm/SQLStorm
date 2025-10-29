-- {"query": "734.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3321} 
with recent_users as (
    select
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(lower(u.websiteurl)), ''), 'n/a') as website_norm,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= now() - interval '3 years'
),
user_badges as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
posts_enriched as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.closeddate,
        p.title,
        p.tags,
        case when p.tags is not null then array_length(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><'), 1) else 0 end as tag_count,
        (p.lastactivitydate - p.creationdate) as active_span,
        case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where p.posttypeid in (1,2)
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        count(*) as total_votes,
        max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
comments_agg as (
    select
        c.postid,
        count(*) as comments_count,
        sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
        max(c.creationdate) as last_comment_at
    from comments c
    group by c.postid
),
links_agg as (
    select
        pl.postid,
        sum(case when pl.linktypeid = 1 then 1 else 0 end) as links_out,
        sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_marks
    from postlinks pl
    group by pl.postid
),
ph_close_reasons as (
    select
        ph.postid,
        -- parse numeric close reason from comment field when PostHistoryTypeId = 10
        max(case when ph.posthistorytypeid = 10 then nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '') end) as close_reason_id_text,
        max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_closed_at
    from posthistory ph
    where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)
    group by ph.postid
),
questions as (
    select
        pe.*,
        va.upvotes,
        va.downvotes,
        va.total_votes,
        va.bounty_started,
        va.bounty_awarded,
        va.last_vote_at,
        ca.comments_count,
        ca.pos_comments,
        ca.last_comment_at,
        la.links_out,
        la.dup_marks,
        ph.first_closed_at,
        cast(ph.close_reason_id_text as int) as close_reason_id
    from posts_enriched pe
    left join votes_agg va on va.postid = pe.id
    left join comments_agg ca on ca.postid = pe.id
    left join links_agg la on la.postid = pe.id
    left join ph_close_reasons ph on ph.postid = pe.id
    where pe.posttypeid = 1
),
answers as (
    select
        pe.*,
        va.upvotes,
        va.downvotes,
        va.total_votes,
        va.bounty_started,
        va.bounty_awarded,
        va.last_vote_at,
        ca.comments_count,
        ca.pos_comments,
        ca.last_comment_at
    from posts_enriched pe
    left join votes_agg va on va.postid = pe.id
    left join comments_agg ca on ca.postid = pe.id
    where pe.posttypeid = 2
),
user_activity as (
    select
        ru.id as userid,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        count(distinct q.id) filter (where q.id is not null) as questions_count,
        count(distinct a.id) filter (where a.id is not null) as answers_count,
        coalesce(sum(q.viewcount),0) as total_question_views,
        coalesce(sum(q.score),0) + coalesce(sum(a.score),0) as total_post_score,
        sum(case when q.is_closed = 1 then 1 else 0 end) as closed_questions,
        sum(coalesce(q.dup_marks,0)) as dup_marks_on_questions,
        sum(coalesce(q.upvotes,0)) + sum(coalesce(a.upvotes,0)) as upvotes_all,
        sum(coalesce(q.downvotes,0)) + sum(coalesce(a.downvotes,0)) as downvotes_all,
        max(greatest(coalesce(q.last_vote_at, timestamp 'epoch'), coalesce(a.last_vote_at, timestamp 'epoch'))) as last_vote_at_any,
        max(greatest(coalesce(q.last_comment_at, timestamp 'epoch'), coalesce(a.last_comment_at, timestamp 'epoch'))) as last_comment_at_any
    from recent_users ru
    left join questions q on q.owneruserid = ru.id
    left join answers a on a.owneruserid = ru.id
    group by ru.id, ru.displayname, ru.reputation, ru.cohort_month
),
answer_accepts as (
    select
        a.owneruserid as userid,
        count(*) as accepted_answers
    from posts q
    join posts a on a.id = q.acceptedanswerid
    group by a.owneruserid
),
tag_explode as (
    select
        q.id as question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
    from questions q
    where q.tags is not null
),
top_tags as (
    select
        te.tagname,
        count(*) as usage_count,
        dense_rank() over (order by count(*) desc) as usage_rank
    from tag_explode te
    group by te.tagname
),
user_top_tag as (
    select
        q.owneruserid as userid,
        te.tagname,
        count(*) as tag_questions,
        row_number() over (partition by q.owneruserid order by count(*) desc, min(q.creationdate)) as rn
    from questions q
    join tag_explode te on te.question_id = q.id
    group by q.owneruserid, te.tagname
),
recent_hot_questions as (
    select
        q.id,
        q.owneruserid,
        q.creationdate,
        q.viewcount,
        q.score,
        q.title,
        sum(coalesce(v2.score,0)) over (partition by q.owneruserid order by q.creationdate rows between unbounded preceding and current row) as cum_user_score
    from questions q
    left join lateral (
        select 1 as score
    ) v2 on true
    where q.creationdate >= now() - interval '18 months'
      and coalesce(q.viewcount,0) > 0
),
user_ranked as (
    select
        ua.userid,
        ua.displayname,
        ua.reputation,
        ua.cohort_month,
        ua.questions_count,
        ua.answers_count,
        ua.total_question_views,
        ua.total_post_score,
        ua.closed_questions,
        ua.dup_marks_on_questions,
        ua.upvotes_all,
        ua.downvotes_all,
        coalesce(aa.accepted_answers,0) as accepted_answers,
        coalesce(ut.tagname, '(none)') as top_tag,
        coalesce(ut.tag_questions,0) as top_tag_questions,
        row_number() over (order by ua.total_post_score desc nulls last, ua.reputation desc, ua.answers_count desc) as global_rownum,
        rank() over (partition by ua.cohort_month order by ua.total_post_score desc nulls last, ua.reputation desc) as cohort_rank,
        avg(ua.total_post_score) over () as avg_total_post_score_all,
        stddev_pop(ua.total_post_score) over () as std_total_post_score_all
    from user_activity ua
    left join answer_accepts aa on aa.userid = ua.userid
    left join user_top_tag ut on ut.userid = ua.userid and ut.rn = 1
),
close_reason_names as (
    select
        crt.id as close_reason_id,
        crt.name as close_reason_name
    from closereasontypes crt
),
question_close_dim as (
    select
        q.id,
        q.owneruserid,
        q.first_closed_at,
        crn.close_reason_name
    from questions q
    left join close_reason_names crn on crn.close_reason_id = q.close_reason_id
),
string_metrics as (
    select
        q.id as question_id,
        length(coalesce(q.title,'')) as title_len,
        coalesce(nullif(regexp_replace(lower(q.title), '[^a-z0-9]+', ' ', 'g'), ''), '') as title_norm,
        case when q.tags is null then 0 else 1 end as has_tags
    from questions q
),
final_agg as (
    select
        ur.userid,
        ur.displayname,
        ur.reputation,
        ur.cohort_month,
        ur.questions_count,
        ur.answers_count,
        ur.accepted_answers,
        ur.total_question_views,
        ur.total_post_score,
        ur.closed_questions,
        ur.dup_marks_on_questions,
        ur.upvotes_all,
        ur.downvotes_all,
        ur.top_tag,
        ur.top_tag_questions,
        ur.global_rownum,
        ur.cohort_rank,
        ur.avg_total_post_score_all,
        ur.std_total_post_score_all,
        -- correlated subquery: recency/velocity on recent hot questions
        (
            select coalesce(avg(rhq.viewcount),0)
            from recent_hot_questions rhq
            where rhq.owneruserid = ur.userid
        ) as avg_recent_q_views,
        (
            select coalesce(max(rhq.cum_user_score),0)
            from recent_hot_questions rhq
            where rhq.owneruserid = ur.userid
        ) as max_cum_user_score,
        -- null-safe favorite ratios
        (
            select coalesce(sum(pe.favoritecount)::numeric,0) / nullif(count(*),0)
            from posts_enriched pe
            where pe.owneruserid = ur.userid and pe.posttypeid = 1
        ) as avg_question_favorites,
        (
            select coalesce(sum(pe.commentcount)::numeric,0) / nullif(count(*),0)
            from posts_enriched pe
            where pe.owneruserid = ur.userid and pe.posttypeid in (1,2)
        ) as avg_comments_per_post
    from user_ranked ur
)
select
    fa.userid,
    fa.displayname,
    fa.reputation,
    to_char(fa.cohort_month, 'YYYY-MM') as cohort_month,
    fa.questions_count,
    fa.answers_count,
    fa.accepted_answers,
    fa.total_question_views,
    fa.total_post_score,
    round(fa.avg_recent_q_views::numeric, 2) as avg_recent_q_views,
    round(fa.max_cum_user_score::numeric, 2) as max_cum_user_score,
    round(fa.avg_question_favorites::numeric, 3) as avg_question_favorites,
    round(fa.avg_comments_per_post::numeric, 3) as avg_comments_per_post,
    fa.closed_questions,
    fa.dup_marks_on_questions,
    fa.upvotes_all,
    fa.downvotes_all,
    fa.top_tag,
    fa.top_tag_questions,
    fa.global_rownum,
    fa.cohort_rank,
    round(coalesce((fa.total_post_score - fa.avg_total_post_score_all) / nullif(fa.std_total_post_score_all,0), 0)::numeric, 3) as zscore_total_post_score,
    -- combine with question-close dimension via set operator to stress planner
    count(distinct qcd.id) as any_closed_questions,
    string_agg(distinct coalesce(qcd.close_reason_name, 'Unknown'), ', ' order by coalesce(qcd.close_reason_name, 'Unknown')) filter (where qcd.close_reason_name is not null) as close_reasons_seen,
    -- windowed aggregates over final output to rank within top tag
    rank() over (partition by fa.top_tag order by fa.total_post_score desc nulls last) as rank_within_tag
from final_agg fa
left join question_close_dim qcd on qcd.owneruserid = fa.userid
where
    -- complicated predicate with null logic and string ops against top tag vs global top tags
    (
        fa.top_tag in (
            select tt.tagname from top_tags tt where tt.usage_rank <= 50
        )
        or (fa.top_tag = '(none)' and fa.questions_count = 0 and fa.answers_count > 0)
    )
    and (
        fa.total_post_score > coalesce(fa.avg_total_post_score_all, 0)
        or (fa.total_post_score is null and fa.reputation > 1000)
    )
group by
    fa.userid, fa.displayname, fa.reputation, fa.cohort_month,
    fa.questions_count, fa.answers_count, fa.accepted_answers,
    fa.total_question_views, fa.total_post_score,
    fa.avg_recent_q_views, fa.max_cum_user_score,
    fa.avg_question_favorites, fa.avg_comments_per_post,
    fa.closed_questions, fa.dup_marks_on_questions,
    fa.upvotes_all, fa.downvotes_all, fa.top_tag,
    fa.top_tag_questions, fa.global_rownum, fa.cohort_rank,
    fa.avg_total_post_score_all, fa.std_total_post_score_all
having
    -- set-based filter to exclude users with only downvotes and no upvotes
    not exists (
        select 1
        from (
            select fa2.userid, sum(fa2.upvotes_all) as u, sum(fa2.downvotes_all) as d
            from final_agg fa2
            where fa2.userid = fa.userid
            group by fa2.userid
        ) s
        where coalesce(s.u,0) = 0 and coalesce(s.d,0) > 0
    )
order by
    zscore_total_post_score desc nulls last,
    fa.total_post_score desc nulls last,
    fa.reputation desc,
    fa.userid
limit 250;