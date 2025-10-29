-- {"query": "295.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2998} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
),
top_recent_users as (
    select *
    from recent_users
    where rn <= 500
),
user_badge_agg as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as questions,
        sum(p.viewcount) filter (where p.posttypeid = 1) as question_views,
        sum(p.score) filter (where p.posttypeid = 1) as question_score,
        count(*) filter (where p.posttypeid = 2) as answers,
        sum(p.score) filter (where p.posttypeid = 2) as answer_score,
        sum(coalesce(p.answercount, 0)) filter (where p.posttypeid = 1) as total_answers_on_questions,
        count(distinct case when p.posttypeid = 1 and p.acceptedanswerid is not null then p.id end) as questions_with_accept,
        max(p.lastactivitydate) as last_post_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
vote_rollup as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_amount
    from votes v
    group by v.postid
),
post_scores as (
    select
        p.owneruserid as user_id,
        sum(coalesce(vr.upvotes,0)) as sum_upvotes_on_posts,
        sum(coalesce(vr.downvotes,0)) as sum_downvotes_on_posts,
        sum(coalesce(vr.favorites,0)) as sum_favorites_on_posts,
        sum(coalesce(vr.bounty_amount,0)) as sum_bounty_amount_on_posts
    from posts p
    left join vote_rollup vr on vr.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as comments_made,
        sum(c.score) as comment_score,
        max(c.creationdate) as last_comment_date,
        avg(length(c.text)) as avg_comment_length
    from comments c
    where c.userid is not null
    group by c.userid
),
post_history_flags as (
    select
        ph.postid,
        sum(case when ph.posthistorytypeid in (10,14,19,50,52,53) then 1 else 0 end) as notable_events,
        max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_closed_date,
        max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopened_date
    from posthistory ph
    group by ph.postid
),
dup_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as related_links
    from postlinks pl
    group by pl.postid
),
tag_exploded as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        lower(trim(tg)) as tag
    from posts p
    cross join lateral unnest(
        case
            when p.tags is null or length(p.tags) < 3 then array[]::varchar[]
            else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
        end
    ) as tg
    where p.posttypeid = 1
),
user_top_tags as (
    select
        te.user_id,
        array_agg(tag order by cnt desc, tag asc)[1:5] as top5_tags,
        max(cnt) as top_tag_count
    from (
        select user_id, tag, count(*) as cnt
        from tag_exploded
        group by user_id, tag
    ) s
    group by user_id
),
question_quality as (
    select
        q.owneruserid as user_id,
        percentile_cont(0.5) within group (order by q.score) as median_q_score,
        avg(nullif(q.viewcount,0)) as avg_q_views_nonzero,
        stddev_pop(coalesce(q.score,0)) as score_stddev,
        count(*) as q_count_for_stats
    from posts q
    where q.posttypeid = 1 and q.owneruserid is not null
    group by q.owneruserid
),
answer_accept_rate as (
    select
        a.owneruserid as user_id,
        count(*) as answers_posted,
        count(*) filter (where a.id in (select acceptedanswerid from posts where acceptedanswerid is not null)) as answers_accepted
    from posts a
    where a.posttypeid = 2 and a.owneruserid is not null
    group by a.owneruserid
),
user_activity_rank as (
    select
        u.id as user_id,
        dense_rank() over (order by coalesce(qa.answers,0) desc, coalesce(qa.questions,0) desc, u.reputation desc) as activity_rank
    from users u
    left join question_activity qa on qa.user_id = u.id
),
normalized_metrics as (
    select
        tru.user_id,
        tru.displayname,
        tru.reputation,
        tru.creationdate,
        tru.location,
        tru.websiteurl,
        coalesce(qa.questions,0) as questions,
        coalesce(qa.answers,0) as answers,
        coalesce(qa.question_views,0) as question_views,
        coalesce(qa.question_score,0) as question_score,
        coalesce(qa.answer_score,0) as answer_score,
        coalesce(qa.total_answers_on_questions,0) as total_answers_on_questions,
        coalesce(qa.questions_with_accept,0) as questions_with_accept,
        qa.last_post_activity,
        coalesce(ps.sum_upvotes_on_posts,0) as sum_upvotes_on_posts,
        coalesce(ps.sum_downvotes_on_posts,0) as sum_downvotes_on_posts,
        coalesce(ps.sum_favorites_on_posts,0) as sum_favorites_on_posts,
        coalesce(ps.sum_bounty_amount_on_posts,0) as sum_bounty_amount_on_posts,
        coalesce(cb.comments_made,0) as comments_made,
        coalesce(cb.comment_score,0) as comment_score,
        cb.last_comment_date,
        coalesce(cb.avg_comment_length,0) as avg_comment_length,
        coalesce(uba.total_badges,0) as total_badges,
        coalesce(uba.gold_badges,0) as gold_badges,
        coalesce(uba.silver_badges,0) as silver_badges,
        coalesce(uba.bronze_badges,0) as bronze_badges,
        coalesce(uba.tag_badges,0) as tag_badges,
        uba.first_badge_date,
        uba.last_badge_date,
        utt.top5_tags,
        coalesce(utt.top_tag_count,0) as top_tag_count,
        qq.median_q_score,
        qq.avg_q_views_nonzero,
        qq.score_stddev,
        aar.answers_posted,
        aar.answers_accepted,
        case when coalesce(aar.answers_posted,0) = 0 then null
             else round(100.0 * coalesce(aar.answers_accepted,0) / nullif(aar.answers_posted,0), 2)
        end as answer_accept_rate_pct,
        uar.activity_rank
    from top_recent_users tru
    left join question_activity qa on qa.user_id = tru.user_id
    left join post_scores ps on ps.user_id = tru.user_id
    left join comment_stats cb on cb.user_id = tru.user_id
    left join user_badge_agg uba on uba.userid = tru.user_id
    left join user_top_tags utt on utt.user_id = tru.user_id
    left join question_quality qq on qq.user_id = tru.user_id
    left join answer_accept_rate aar on aar.user_id = tru.user_id
    left join user_activity_rank uar on uar.user_id = tru.user_id
),
scored as (
    select
        nm.*,
        -- composite score with various weights; safe NULL handling
        (
            0.30 * ln(1 + greatest(nm.reputation,0)) +
            0.15 * ln(1 + greatest(nm.questions,0) + greatest(nm.answers,0)) +
            0.10 * ln(1 + greatest(nm.sum_upvotes_on_posts - nm.sum_downvotes_on_posts, 0)) +
            0.10 * coalesce(nm.answer_accept_rate_pct, 0) / 100.0 +
            0.10 * ln(1 + greatest(nm.total_badges,0)) +
            0.10 * ln(1 + greatest(nm.question_views,0)) +
            0.05 * coalesce(nm.median_q_score, 0) +
            0.05 * ln(1 + greatest(nm.sum_bounty_amount_on_posts,0))
        ) as composite_score
    from normalized_metrics nm
),
ranked as (
    select
        s.*,
        row_number() over (order by s.composite_score desc, s.reputation desc, s.user_id asc) as rownum,
        ntile(10) over (order by s.composite_score desc) as decile
    from scored s
),
stringified as (
    select
        r.*,
        -- Build a descriptive string summary with careful NULL handling
        (
            'User ' || coalesce(r.displayname, '[unknown]') ||
            ' (ID ' || r.user_id || ', rep ' || r.reputation || ')' ||
            ' • Q/A: ' || coalesce(r.questions,0) || '/' || coalesce(r.answers,0) ||
            ' • Votes: +' || coalesce(r.sum_upvotes_on_posts,0) || '/-' || coalesce(r.sum_downvotes_on_posts,0) ||
            ' • Fav: ' || coalesce(r.sum_favorites_on_posts,0) ||
            ' • Badges G/S/B: ' || coalesce(r.gold_badges,0) || '/' || coalesce(r.silver_badges,0) || '/' || coalesce(r.bronze_badges,0) ||
            ' • Top tags: ' || coalesce(array_to_string(r.top5_tags, ', '), '[none]') ||
            ' • AcceptRate: ' || coalesce(r.answer_accept_rate_pct::text, 'N/A') || '%' ||
            ' • Score: ' || round(r.composite_score::numeric, 4)
        ) as summary
    from ranked r
)
select
    s.user_id,
    s.displayname,
    s.location,
    s.websiteurl,
    s.creationdate,
    s.reputation,
    s.questions,
    s.answers,
    s.question_views,
    s.question_score,
    s.answer_score,
    s.questions_with_accept,
    s.total_answers_on_questions,
    s.sum_upvotes_on_posts,
    s.sum_downvotes_on_posts,
    s.sum_favorites_on_posts,
    s.sum_bounty_amount_on_posts,
    s.comments_made,
    s.comment_score,
    s.avg_comment_length,
    s.total_badges,
    s.gold_badges,
    s.silver_badges,
    s.bronze_badges,
    s.tag_badges,
    s.first_badge_date,
    s.last_badge_date,
    s.top5_tags,
    s.top_tag_count,
    s.median_q_score,
    s.avg_q_views_nonzero,
    s.score_stddev,
    s.answers_posted,
    s.answers_accepted,
    s.answer_accept_rate_pct,
    s.activity_rank,
    s.composite_score,
    s.decile,
    s.rownum,
    s.summary
from stringified s
where (
    -- complex predicate combining multiple signals and NULL-aware logic
    (
        coalesce(s.reputation,0) > 1000
        and (coalesce(s.answers,0) >= 5 or coalesce(s.questions,0) >= 5)
        and coalesce(s.sum_upvotes_on_posts,0) >= coalesce(s.sum_downvotes_on_posts,0)
    )
    or (
        s.answer_accept_rate_pct is not null
        and s.answer_accept_rate_pct >= 50
        and coalesce(s.answers_posted,0) >= 3
    )
    or (
        s.total_badges >= 10
        and coalesce(s.gold_badges,0) >= 1
    )
)
order by s.decile, s.rownum
limit 200;