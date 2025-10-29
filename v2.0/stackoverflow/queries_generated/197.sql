-- {"query": "197.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3174} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        u.upvotes,
        u.downvotes,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_badge_rollup as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
questions_cte as (
    select
        p.id as question_id,
        p.owneruserid as owner_user_id,
        p.creationdate as q_created,
        p.score as q_score,
        p.viewcount as q_views,
        p.answercount as q_answers,
        p.favoritecount as q_favs,
        p.closeddate as q_closed,
        p.title,
        p.tags,
        array_length(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><'), 1) as tag_count
    from posts p
    where p.posttypeid = 1
),
answers_cte as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answer_user_id,
        a.creationdate as a_created,
        a.score as a_score
    from posts a
    where a.posttypeid = 2
),
q_activity as (
    select
        q.question_id,
        q.owner_user_id,
        q.q_created,
        q.q_score,
        q.q_views,
        q.q_answers,
        q.q_favs,
        q.q_closed,
        q.title,
        q.tags,
        q.tag_count,
        count(c.id) as comment_count,
        count(v.id) filter (where v.votetypeid = 2) as upvotes_count,
        count(v.id) filter (where v.votetypeid = 3) as downvotes_count,
        count(v.id) filter (where v.votetypeid = 5) as favorite_votes_count
    from questions_cte q
    left join comments c on c.postid = q.question_id
    left join votes v on v.postid = q.question_id
    group by q.question_id, q.owner_user_id, q.q_created, q.q_score, q.q_views, q.q_answers, q.q_favs, q.q_closed, q.title, q.tags, q.tag_count
),
answer_stats as (
    select
        a.question_id,
        count(*) as answers_total,
        avg(a.a_score::numeric) as avg_answer_score,
        max(a.a_score) as max_answer_score,
        min(a.a_score) as min_answer_score,
        sum(case when a.a_score > 0 then 1 else 0 end) as positive_answers,
        sum(case when a.a_score < 0 then 1 else 0 end) as negative_answers,
        max(a.a_created) as last_answer_date
    from answers_cte a
    group by a.question_id
),
accepted_answer as (
    select
        q.id as question_id,
        aa.id as accepted_answer_id,
        aa.owneruserid as accepted_owner_id,
        aa.score as accepted_score,
        aa.creationdate as accepted_created
    from posts q
    join posts aa on aa.id = q.acceptedanswerid
    where q.posttypeid = 1
),
postlink_dups as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        pl.creationdate as dup_link_date
    from postlinks pl
    where pl.linktypeid = 3
),
tag_explode as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tagname
    from questions_cte q
),
tag_stats as (
    select
        te.question_id,
        count(*) as distinct_tags_on_q,
        max(t.count) filter (where t.tagname = te.tagname) as tag_global_count_max,
        sum(case when t.isrequired = 1 then 1 else 0 end) as required_tag_count,
        sum(case when t.ismoderatoronly = 1 then 1 else 0 end) as modonly_tag_count
    from tag_explode te
    left join tags t on lower(t.tagname) = lower(te.tagname)
    group by te.question_id
),
posthistory_flags as (
    select
        ph.postid as question_id,
        max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as was_closed_or_migrated,
        max(case when ph.posthistorytypeid in (11) then 1 else 0 end) as was_reopened,
        max(case when ph.posthistorytypeid in (19) then 1 else 0 end) as was_protected,
        max(case when ph.posthistorytypeid in (24) then 1 else 0 end) as had_suggested_edit
    from posthistory ph
    join posts p on p.id = ph.postid and p.posttypeid = 1
    group by ph.postid
),
user_quality as (
    select
        u.id as user_id,
        percentile_cont(0.5) within group (order by coalesce(p.score,0)) as median_post_score,
        avg(coalesce(p.score,0)::numeric) as avg_post_score,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as q_count,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as a_count,
        sum(case when p.posttypeid = 1 and p.acceptedanswerid is not null then 1 else 0 end) as qs_with_accepted,
        sum(case when p.posttypeid = 2 and exists (
            select 1
            from posts q2
            where q2.posttypeid = 1
              and q2.acceptedanswerid = p.id
        ) then 1 else 0 end) as accepted_answers_by_user
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
recent_activity_window as (
    select
        qa.question_id,
        qa.q_created,
        qa.q_score,
        qa.q_views,
        qa.q_answers,
        qa.q_favs,
        qa.comment_count,
        qa.upvotes_count,
        qa.downvotes_count,
        sum(qa.q_views) over (order by qa.q_created rows between unbounded preceding and current row) as cum_views_by_time,
        avg(qa.q_score::numeric) over (partition by date_trunc('month', qa.q_created)) as avg_score_by_month,
        rank() over (order by qa.q_views desc nulls last) as rank_by_views
    from q_activity qa
),
hot_candidates as (
    select
        r.question_id,
        case
            when r.q_views > 0 then round((r.upvotes_count::numeric - r.downvotes_count::numeric) / greatest(r.q_views::numeric, 1) * 100, 4)
            else null
        end as hotness_ratio,
        r.rank_by_views,
        r.avg_score_by_month
    from recent_activity_window r
),
complex_filter as (
    select
        qa.question_id,
        qa.owner_user_id,
        qa.q_created,
        qa.q_score,
        qa.q_views,
        qa.q_answers,
        qa.q_favs,
        qa.comment_count,
        ts.distinct_tags_on_q,
        ts.required_tag_count,
        ts.modonly_tag_count,
        ph.was_closed_or_migrated,
        ph.was_reopened,
        ph.was_protected,
        ph.had_suggested_edit,
        ah.accepted_answer_id,
        ah.accepted_owner_id,
        ah.accepted_score,
        ah.accepted_created,
        asf.answers_total,
        asf.avg_answer_score,
        asf.max_answer_score,
        asf.min_answer_score,
        asf.positive_answers,
        asf.negative_answers,
        asf.last_answer_date,
        hc.hotness_ratio,
        hc.rank_by_views,
        hc.avg_score_by_month
    from q_activity qa
    left join tag_stats ts on ts.question_id = qa.question_id
    left join posthistory_flags ph on ph.question_id = qa.question_id
    left join accepted_answer ah on ah.question_id = qa.question_id
    left join answer_stats asf on asf.question_id = qa.question_id
    left join hot_candidates hc on hc.question_id = qa.question_id
    where
        (
            qa.q_score >= 5
            or (qa.q_views >= 1000 and qa.q_answers >= 2)
            or (coalesce(ts.required_tag_count,0) >= 1 and qa.q_views >= 500)
        )
        and not (ph.was_closed_or_migrated = 1 and coalesce(ph.was_reopened,0) = 0)
),
user_enriched as (
    select
        cf.*,
        u.displayname,
        u.reputation,
        u.location,
        ubr.total_badges,
        ubr.gold_badges,
        ubr.silver_badges,
        ubr.bronze_badges,
        uq.median_post_score,
        uq.avg_post_score,
        uq.q_count,
        uq.a_count,
        uq.qs_with_accepted,
        uq.accepted_answers_by_user,
        ru.websiteurl_norm,
        case
            when uq.a_count + uq.q_count > 0 then round((uq.accepted_answers_by_user::numeric) / greatest(uq.a_count::numeric, 1), 4)
            else 0
        end as accepted_answer_rate
    from complex_filter cf
    left join users u on u.id = cf.owner_user_id
    left join user_badge_rollup ubr on ubr.userid = cf.owner_user_id
    left join user_quality uq on uq.user_id = cf.owner_user_id
    left join recent_users ru on ru.user_id = cf.owner_user_id
),
scored as (
    select
        ue.*,
        -- composite score blending question, user, and community signals
        round((
            coalesce(ue.q_score,0) * 0.35
            + coalesce(ue.hotness_ratio,0) * 0.20
            + coalesce(ue.avg_answer_score,0) * 0.10
            + least(coalesce(ue.q_views,0) / 1000.0, 50) * 0.08
            + coalesce(ue.total_badges,0) * 0.02
            + coalesce(ue.reputation,0) / 1000.0 * 0.15
            + (case when ue.was_protected = 1 then -2 else 0 end)
            + (case when ue.modonly_tag_count > 0 then -1 else 0 end)
            + (case when ue.accepted_answer_id is not null then 1.5 else 0 end)
        )::numeric, 4) as composite_score
    from user_enriched ue
),
null_safety as (
    select
        s.*,
        coalesce(nullif(btrim(coalesce(p.title, s.title)), ''), '(untitled)') as title_safe,
        coalesce(s.distinct_tags_on_q, 0) as distinct_tags_on_q_safe,
        coalesce(s.answers_total, 0) as answers_total_safe
    from scored s
    left join posts p on p.id = s.question_id
),
dup_info as (
    select
        d.dup_post_id as question_id,
        count(*) as dup_count,
        min(d.dup_link_date) as first_dup_date
    from postlink_dups d
    group by d.dup_post_id
),
final_ranked as (
    select
        ns.*,
        di.dup_count,
        di.first_dup_date,
        row_number() over (
            partition by date_trunc('month', ns.q_created)
            order by ns.composite_score desc nulls last, ns.q_views desc nulls last
        ) as month_rank
    from null_safety ns
    left join dup_info di on di.question_id = ns.question_id
)
select
    fr.question_id,
    fr.title_safe as title,
    fr.tags,
    fr.q_created,
    fr.q_score,
    fr.q_views,
    fr.answers_total_safe as answers_total,
    fr.avg_answer_score,
    fr.accepted_answer_id,
    fr.accepted_score,
    fr.last_answer_date,
    fr.comment_count,
    fr.distinct_tags_on_q_safe as tag_count,
    fr.required_tag_count,
    fr.modonly_tag_count,
    fr.was_protected,
    fr.had_suggested_edit,
    fr.dup_count,
    fr.first_dup_date,
    fr.displayname as owner_name,
    fr.reputation,
    fr.total_badges,
    fr.gold_badges,
    fr.silver_badges,
    fr.bronze_badges,
    fr.median_post_score,
    fr.avg_post_score,
    fr.q_count,
    fr.a_count,
    fr.accepted_answers_by_user,
    fr.accepted_answer_rate,
    fr.hotness_ratio,
    fr.rank_by_views,
    fr.avg_score_by_month,
    fr.composite_score,
    fr.month_rank
from final_ranked fr
where
    -- diverse complex predicate mixing null logic, string search, and numeric thresholds
    coalesce(fr.composite_score, 0) > 1.0
    and (fr.title ilike any (array['%performance%','%optimiz%','%index%','%join%']) or fr.q_views > 5000 or fr.answers_total_safe >= 5)
    and (
        fr.location is null
        or fr.location ilike '%us%'
        or fr.location ilike '%europe%'
        or fr.location ~* '(canada|india|singapore)'
    )
    and not (fr.modonly_tag_count > 0 and fr.reputation < 1000)
    and (fr.q_created >= now() - interval '5 years' or fr.accepted_answer_id is not null)
order by fr.composite_score desc, fr.q_views desc, fr.q_created desc
limit 250;