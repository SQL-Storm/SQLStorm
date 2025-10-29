-- {"query": "796.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3325} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        coalesce(nullif(trim(split_part(coalesce(u.location, 'Unknown'), ',', 1)), ''), 'Unknown') as country_guess,
        case
            when u.websiteurl ilike '%github.com%' then 1
            when u.aboutme ilike '%github%' then 1
            else 0
        end as is_githubby
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        avg(nullif(p.score, 0)) as avg_nonzero_score,
        sum(coalesce(p.viewcount, 0)) as total_views,
        max(p.lastactivitydate) as last_post_activity,
        count(*) filter (where p.closeddate is not null) as closed_posts,
        sum(p.commentcount) as total_comments_on_posts
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
answer_quality as (
    select
        p.owneruserid as user_id,
        percentile_cont(0.5) within group (order by coalesce(p.score, 0)) as ans_score_median,
        avg(p.score) as ans_score_avg,
        stddev_pop(p.score) as ans_score_std,
        count(*) filter (where p.acceptedanswerid is not null) as self_accepted_questions,
        count(*) as total_ans_or_q
    from posts p
    where p.posttypeid in (1,2)
    group by p.owneruserid
),
vote_agg as (
    select
        v.userid as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_cast,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_cast,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_cast,
        count(*) filter (where v.votetypeid in (2,3)) as total_votes_cast,
        min(v.creationdate) as first_vote_date,
        max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
    group by v.userid
),
badge_agg as (
    select
        b.userid as user_id,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges,
        count(*) as total_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
comment_engagement as (
    select
        c.userid as user_id,
        count(*) as comments_made,
        avg(c.score) as avg_comment_score,
        sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
        sum(case when c.score < 0 then 1 else 0 end) as neg_comments,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
tag_popularity as (
    select
        p.owneruserid as user_id,
        array_agg(distinct t.tagname) filter (where t.tagname is not null) as distinct_tags_used,
        sum(t.count) as sum_tag_popularity
    from posts p
    join lateral (
        select unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
    ) tt on p.posttypeid = 1 and p.tags is not null
    left join tags t on t.tagname = tt.tagname
    where p.owneruserid is not null
    group by p.owneruserid
),
postlinks_agg as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        count(*) filter (where pl.linktypeid = 3) as duplicate_count
    from postlinks pl
    group by pl.postid
),
question_rollups as (
    select
        p.owneruserid as user_id,
        count(*) as questions,
        avg(p.viewcount) as avg_views_per_q,
        sum(case when coalesce(pl.duplicate_count,0) > 0 then 1 else 0 end) as q_marked_duplicate,
        sum(case when exists (
            select 1
            from posthistory ph
            where ph.postid = p.id
              and ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)
        ) then 1 else 0 end) as q_moderation_events
    from posts p
    left join postlinks_agg pl on pl.postid = p.id
    where p.posttypeid = 1 and p.owneruserid is not null
    group by p.owneruserid
),
accepted_answerers as (
    select
        a.owneruserid as user_id,
        count(*) as accepted_answers
    from posts q
    join posts a on a.id = q.acceptedanswerid and a.posttypeid = 2
    where q.posttypeid = 1 and a.owneruserid is not null
    group by a.owneruserid
),
temporal_activity as (
    select
        p.owneruserid as user_id,
        date_trunc('month', p.creationdate) as month_bucket,
        count(*) as posts_in_month
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid, date_trunc('month', p.creationdate)
),
temporal_stats as (
    select
        user_id,
        avg(posts_in_month) as avg_posts_per_active_month,
        max(posts_in_month) as max_posts_in_a_month,
        count(*) as active_months
    from temporal_activity
    group by user_id
),
user_ranked as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.country_guess,
        ru.is_githubby,
        coalesce(ua.q_count,0) as q_count,
        coalesce(ua.a_count,0) as a_count,
        coalesce(ua.avg_nonzero_score,0) as avg_nonzero_score,
        coalesce(ua.total_views,0) as total_views,
        ua.last_post_activity,
        coalesce(ua.closed_posts,0) as closed_posts,
        coalesce(ua.total_comments_on_posts,0) as total_comments_on_posts,
        coalesce(aq.ans_score_median,0) as ans_score_median,
        coalesce(aq.ans_score_avg,0) as ans_score_avg,
        coalesce(aq.ans_score_std,0) as ans_score_std,
        coalesce(aa.accepted_answers,0) as accepted_answers,
        coalesce(va.upvotes_cast,0) as upvotes_cast,
        coalesce(va.downvotes_cast,0) as downvotes_cast,
        coalesce(va.favorites_cast,0) as favorites_cast,
        va.first_vote_date,
        va.last_vote_date,
        coalesce(ba.gold_badges,0) as gold_badges,
        coalesce(ba.silver_badges,0) as silver_badges,
        coalesce(ba.bronze_badges,0) as bronze_badges,
        coalesce(ba.tag_badges,0) as tag_badges,
        coalesce(ba.total_badges,0) as total_badges,
        ba.last_badge_date,
        coalesce(ce.comments_made,0) as comments_made,
        coalesce(ce.avg_comment_score,0) as avg_comment_score,
        coalesce(ce.pos_comments,0) as pos_comments,
        coalesce(ce.neg_comments,0) as neg_comments,
        ce.last_comment_date,
        tp.distinct_tags_used,
        coalesce(tp.sum_tag_popularity,0) as sum_tag_popularity,
        coalesce(qr.questions,0) as questions,
        coalesce(qr.avg_views_per_q,0) as avg_views_per_q,
        coalesce(qr.q_marked_duplicate,0) as q_marked_duplicate,
        coalesce(qr.q_moderation_events,0) as q_moderation_events,
        coalesce(ts.avg_posts_per_active_month,0) as avg_posts_per_active_month,
        coalesce(ts.max_posts_in_a_month,0) as max_posts_in_a_month,
        coalesce(ts.active_months,0) as active_months
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join answer_quality aq on aq.user_id = ru.user_id
    left join accepted_answerers aa on aa.user_id = ru.user_id
    left join vote_agg va on va.user_id = ru.user_id
    left join badge_agg ba on ba.user_id = ru.user_id
    left join comment_engagement ce on ce.user_id = ru.user_id
    left join tag_popularity tp on tp.user_id = ru.user_id
    left join question_rollups qr on qr.user_id = ru.user_id
    left join temporal_stats ts on ts.user_id = ru.user_id
),
scored as (
    select
        ur.*,
        -- Composite scoring with NULL-safe math and non-linear components
        (
            0.40 * ln(1 + greatest(ur.a_count,0)) +
            0.20 * ln(1 + greatest(ur.q_count,0)) +
            0.25 * greatest(ur.ans_score_avg, 0) +
            0.15 * ln(1 + greatest(ur.accepted_answers,0)) +
            0.10 * ln(1 + greatest(ur.total_badges,0)) +
            0.05 * ln(1 + greatest(ur.sum_tag_popularity,0)) +
            0.10 * ln(1 + greatest(ur.total_views,0)) -
            0.08 * ln(1 + greatest(ur.closed_posts,0)) -
            0.05 * ln(1 + greatest(ur.q_marked_duplicate,0)) -
            0.03 * greatest(ur.neg_comments - ur.pos_comments, 0)
        ) +
        case when ur.is_githubby = 1 then 0.05 else 0 end as raw_score
    from user_ranked ur
),
ranked as (
    select
        s.*,
        row_number() over (order by s.raw_score desc, s.reputation desc, s.last_post_activity desc nulls last) as rn,
        rank() over (order by s.reputation desc) as rep_rank,
        dense_rank() over (order by s.total_badges desc) as badge_rank,
        percent_rank() over (order by s.raw_score) as score_percentile,
        ntile(10) over (order by s.raw_score desc) as score_decile
    from scored s
),
outliers as (
    select
        r.user_id,
        case when r.ans_score_std > 0 and abs(r.ans_score_avg - r.ans_score_median) / r.ans_score_std > 2 then 1 else 0 end as answer_score_outlier,
        case when r.avg_posts_per_active_month > 0 and r.max_posts_in_a_month > 5 * r.avg_posts_per_active_month then 1 else 0 end as bursty_poster
    from ranked r
),
final_union as (
    select
        r.user_id,
        r.displayname,
        r.country_guess,
        r.reputation,
        r.rep_rank,
        r.badge_rank,
        r.raw_score,
        r.score_percentile,
        r.score_decile,
        r.q_count,
        r.a_count,
        r.accepted_answers,
        r.total_badges,
        r.gold_badges,
        r.silver_badges,
        r.bronze_badges,
        r.upvotes_cast,
        r.downvotes_cast,
        r.favorites_cast,
        r.total_views,
        r.avg_nonzero_score,
        r.ans_score_avg,
        r.ans_score_median,
        r.ans_score_std,
        r.questions,
        r.avg_views_per_q,
        r.q_marked_duplicate,
        r.q_moderation_events,
        r.comments_made,
        r.avg_comment_score,
        r.pos_comments,
        r.neg_comments,
        r.active_months,
        r.avg_posts_per_active_month,
        r.max_posts_in_a_month,
        r.last_post_activity,
        r.last_vote_date,
        r.last_badge_date,
        r.last_comment_date,
        array_to_string(coalesce(r.distinct_tags_used, array[]::varchar[]), ',') as tags_used_csv,
        o.answer_score_outlier,
        o.bursty_poster
    from ranked r
    left join outliers o on o.user_id = r.user_id

    union all

    select
        null::int as user_id,
        'ALL_USERS_SUMMARY'::varchar as displayname,
        'ALL'::varchar as country_guess,
        null::int as reputation,
        null::bigint as rep_rank,
        null::bigint as badge_rank,
        avg(raw_score) as raw_score,
        null::float as score_percentile,
        null::int as score_decile,
        sum(q_count)::bigint,
        sum(a_count)::bigint,
        sum(accepted_answers)::bigint,
        sum(total_badges)::bigint,
        sum(gold_badges)::bigint,
        sum(silver_badges)::bigint,
        sum(bronze_badges)::bigint,
        sum(upvotes_cast)::bigint,
        sum(downvotes_cast)::bigint,
        sum(favorites_cast)::bigint,
        sum(total_views)::bigint,
        avg(avg_nonzero_score),
        avg(ans_score_avg),
        avg(ans_score_median),
        avg(ans_score_std),
        sum(questions)::bigint,
        avg(avg_views_per_q),
        sum(q_marked_duplicate)::bigint,
        sum(q_moderation_events)::bigint,
        sum(comments_made)::bigint,
        avg(avg_comment_score),
        sum(pos_comments)::bigint,
        sum(neg_comments)::bigint,
        sum(active_months)::bigint,
        avg(avg_posts_per_active_month),
        max(max_posts_in_a_month),
        max(last_post_activity),
        max(last_vote_date),
        max(last_badge_date),
        max(last_comment_date),
        null::varchar as tags_used_csv,
        null::int as answer_score_outlier,
        null::int as bursty_poster
    from ranked
)
select *
from final_union
where (user_id is null or rn <= 200)
order by coalesce(raw_score, -1) desc nulls last, coalesce(reputation, -1) desc nulls last, coalesce(last_post_activity, timestamp 'epoch') desc nulls last;