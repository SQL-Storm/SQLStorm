-- {"query": "477.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3230} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (partition by date_trunc('month', u.creationdate) order by u.reputation desc, u.id) as rn_in_cohort
    from users u
    where u.creationdate >= (select max(p.creationdate) - interval '365 days' from posts p)
),
qna as (
    select
        p.id,
        p.posttypeid,
        p.creationdate,
        p.owneruserid,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        case when p.posttypeid = 1 then 1 else 0 end as is_question,
        case when p.posttypeid = 2 then 1 else 0 end as is_answer
    from posts p
    where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
tag_arr as (
    select
        id,
        string_to_array(substring(tags, 2, greatest(length(tags)-2,0)), '><') as tag_list
    from qna
    where tags is not null
),
exploded_tags as (
    select
        ta.id as post_id,
        lower(trim(t)) as tag
    from tag_arr ta
    cross join lateral unnest(ta.tag_list) as t
),
user_tag_activity as (
    select
        u.user_id,
        et.tag,
        count(*) filter (where q.is_question = 1) as questions,
        count(*) filter (where q.is_answer = 1) as answers,
        sum(q.score) as total_score,
        sum(coalesce(q.viewcount,0)) as total_views,
        avg(nullif(q.score,0)) filter (where q.score is not null) as avg_score_nonzero
    from recent_users u
    join qna q on q.owneruserid = u.user_id
    left join exploded_tags et on et.post_id = q.id
    group by u.user_id, et.tag
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        min(v.creationdate) as first_vote_at,
        max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
answers_with_parent as (
    select
        a.id as answer_id,
        a.owneruserid as answer_user_id,
        a.score as answer_score,
        a.creationdate as answer_created,
        q.id as question_id,
        q.owneruserid as question_user_id,
        q.creationdate as question_created,
        q.title as question_title,
        q.tags as question_tags,
        q.score as question_score
    from posts a
    join posts q on q.id = a.parentid
    where a.posttypeid = 2
      and q.posttypeid = 1
      and a.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
accepted_info as (
    select
        q.id as question_id,
        q.acceptedanswerid as accepted_answer_id
    from posts q
    where q.posttypeid = 1
),
post_closure as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_raw
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
duplicate_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_count,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
badge_ranks as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as gold,
        count(*) filter (where b.class = 2) as silver,
        count(*) filter (where b.class = 3) as bronze,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
user_summary as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        ru.rn_in_cohort,
        br.gold,
        br.silver,
        br.bronze,
        br.last_badge_date,
        coalesce(sum(uta.questions),0) as total_questions,
        coalesce(sum(uta.answers),0) as total_answers,
        coalesce(sum(uta.total_score),0) as total_post_score,
        coalesce(sum(uta.total_views),0) as total_post_views,
        count(distinct uta.tag) as distinct_tags
    from recent_users ru
    left join badge_ranks br on br.userid = ru.user_id
    left join user_tag_activity uta on uta.user_id = ru.user_id
    group by ru.user_id, ru.displayname, ru.reputation, ru.cohort_month, ru.rn_in_cohort, br.gold, br.silver, br.bronze, br.last_badge_date
),
question_metrics as (
    select
        q.id as question_id,
        q.owneruserid as owner_user_id,
        q.creationdate,
        q.title,
        q.tags,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.favorites,0) as favorites,
        coalesce(va.bounty_total,0) as bounty_total,
        va.first_vote_at,
        va.last_vote_at,
        pc.first_closed_at,
        pc.last_reopened_at,
        pc.last_close_reason_raw,
        dl.duplicate_count,
        dl.linked_count,
        dl.last_link_date,
        (select count(*) from comments c where c.postid = q.id and c.score > 0) as pos_comment_count,
        (select count(*) from posts a where a.parentid = q.id and a.posttypeid = 2) as answer_count_actual
    from posts q
    left join votes_agg va on va.postid = q.id
    left join post_closure pc on pc.postid = q.id
    left join duplicate_links dl on dl.postid = q.id
    where q.posttypeid = 1
      and q.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
answer_metrics as (
    select
        a.answer_id,
        a.question_id,
        a.answer_user_id,
        a.answer_score,
        a.answer_created,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.favorites,0) as favorites
    from answers_with_parent a
    left join votes_agg va on va.postid = a.answer_id
),
accepted_flags as (
    select
        am.*,
        case when am.answer_id = ai.accepted_answer_id then 1 else 0 end as is_accepted
    from answer_metrics am
    left join accepted_info ai on ai.question_id = am.question_id
),
question_quality as (
    select
        qm.question_id,
        qm.owner_user_id,
        qm.creationdate,
        qm.title,
        qm.tags,
        qm.upvotes,
        qm.downvotes,
        qm.favorites,
        qm.bounty_total,
        qm.first_vote_at,
        qm.last_vote_at,
        qm.first_closed_at,
        qm.last_reopened_at,
        qm.last_close_reason_raw,
        qm.duplicate_count,
        qm.linked_count,
        qm.last_link_date,
        qm.pos_comment_count,
        qm.answer_count_actual,
        -- Composite score with dampening and penalties
        (
            (qm.upvotes - 1.5 * qm.downvotes) +
            ln(1 + coalesce(qm.favorites,0)) * 2 +
            case when qm.first_closed_at is not null then -5 else 0 end +
            case when qm.duplicate_count > 0 then -2 * least(qm.duplicate_count, 5) else 0 end +
            case when qm.bounty_total > 0 then least(qm.bounty_total / 50.0, 10) else 0 end +
            least(coalesce(qm.pos_comment_count,0), 10) * 0.5
        ) as composite_quality
    from question_metrics qm
),
user_activity_windows as (
    select
        us.user_id,
        us.displayname,
        us.reputation,
        us.cohort_month,
        us.rn_in_cohort,
        us.gold, us.silver, us.bronze, us.last_badge_date,
        sum(case when qq.creationdate >= now() - interval '30 days' then 1 else 0 end) as questions_30d,
        sum(case when qq.creationdate >= now() - interval '90 days' then 1 else 0 end) as questions_90d,
        avg(qq.composite_quality) as avg_quality_all,
        avg(qq.composite_quality) filter (where qq.creationdate >= now() - interval '90 days') as avg_quality_90d,
        percentile_cont(0.5) within group (order by qq.composite_quality) as median_quality,
        max(qq.composite_quality) as max_quality
    from user_summary us
    left join question_quality qq on qq.owner_user_id = us.user_id
    group by us.user_id, us.displayname, us.reputation, us.cohort_month, us.rn_in_cohort, us.gold, us.silver, us.bronze, us.last_badge_date
),
best_answerers as (
    select
        af.answer_user_id as user_id,
        count(*) as answers_total,
        sum(case when af.is_accepted = 1 then 1 else 0 end) as accepts_total,
        avg(af.answer_score) as avg_answer_score,
        avg(case when af.is_accepted = 1 then af.answer_score end) as avg_score_when_accepted,
        100.0 * sum(case when af.is_accepted = 1 then 1 else 0 end) / nullif(count(*),0) as accept_rate_pct
    from accepted_flags af
    group by af.answer_user_id
),
close_reason_map as (
    select
        ph.postid,
        case
            when ph.posthistorytypeid = 10 then
                trim(both '"' from split_part(coalesce(ph.comment,''), ':', 1))
            else null
        end as close_reason_code
    from posthistory ph
    where ph.posthistorytypeid = 10
),
final_rank as (
    select
        uaw.*,
        coalesce(ba.answers_total,0) as answers_total,
        coalesce(ba.accepts_total,0) as accepts_total,
        coalesce(ba.avg_answer_score,0) as avg_answer_score,
        coalesce(ba.avg_score_when_accepted,0) as avg_score_when_accepted,
        coalesce(ba.accept_rate_pct,0) as accept_rate_pct,
        rank() over (
            order by
                coalesce(uaw.avg_quality_90d, uaw.avg_quality_all) desc nulls last,
                uaw.questions_90d desc,
                ba.accept_rate_pct desc nulls last,
                uaw.reputation desc
        ) as perf_rank
    from user_activity_windows uaw
    left join best_answerers ba on ba.user_id = uaw.user_id
)
select
    fr.perf_rank,
    fr.user_id,
    fr.displayname,
    fr.reputation,
    fr.cohort_month,
    fr.rn_in_cohort,
    fr.gold, fr.silver, fr.bronze,
    fr.questions_30d,
    fr.questions_90d,
    round(coalesce(fr.avg_quality_90d, fr.avg_quality_all)::numeric, 3) as avg_quality,
    round(fr.median_quality::numeric, 3) as median_quality,
    fr.max_quality,
    fr.answers_total,
    fr.accepts_total,
    round(fr.accept_rate_pct::numeric, 2) as accept_rate_pct,
    fr.avg_answer_score,
    fr.avg_score_when_accepted,
    -- Breakdown by top 3 tags per user (concatenated)
    (
        select string_agg(tag || ':' || totals, ', ' order by totals::int desc, tag)
        from (
            select
                coalesce(uta.tag, '(no-tag)') as tag,
                (coalesce(uta.questions,0) + coalesce(uta.answers,0))::text as totals,
                row_number() over (order by coalesce(uta.questions,0) + coalesce(uta.answers,0) desc, coalesce(uta.tag,'')) as rn
            from user_tag_activity uta
            where uta.user_id = fr.user_id
        ) s
        where s.rn <= 3
    ) as top_tags_summary,
    -- Example of correlated subquery with null-handling: last closed reason code seen on any of user's questions
    (
        select crm.close_reason_code
        from question_metrics qm
        join close_reason_map crm on crm.postid = qm.question_id
        where qm.owner_user_id = fr.user_id
        order by qm.first_closed_at desc nulls last
        limit 1
    ) as last_close_reason_code,
    -- NULL logic and string expressions on website url
    case
        when position('github' in coalesce((select websiteurl_norm from recent_users ru where ru.user_id = fr.user_id), '')) > 0 then 'github'
        when position('stack' in coalesce((select websiteurl_norm from recent_users ru where ru.user_id = fr.user_id), '')) > 0 then 'stack'
        when coalesce((select websiteurl_norm from recent_users ru where ru.user_id = fr.user_id), 'n/a') = 'n/a' then 'none'
        else 'other'
    end as website_kind
from final_rank fr
where (fr.questions_90d > 0 or fr.answers_total > 0)
qualify fr.perf_rank <= 200;