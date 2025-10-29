-- {"query": "855.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3447}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_newest,
        ntile(10) over (order by u.reputation desc) as rep_decile
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) from users)
),
question_activity as (
    select
        p.owneruserid as user_id,
        p.id as question_id,
        p.creationdate as q_created,
        p.score as q_score,
        p.viewcount as q_views,
        p.favoritecount as q_favs,
        p.answercount as q_answers,
        coalesce(p.closeddate, timestamp '1970-01-01') as closed_at,
        coalesce(p.title, '') as title,
        p.tags,
        dense_rank() over (partition by p.owneruserid order by p.score desc nulls last, p.viewcount desc nulls last, p.id) as drank_by_score
    from posts p
    where p.posttypeid = 1
),
answer_activity as (
    select
        p.owneruserid as user_id,
        p.parentid as question_id,
        p.id as answer_id,
        p.creationdate as a_created,
        p.score as a_score,
        lead(p.score) over (partition by p.parentid order by p.score desc, p.id) as next_answer_score_same_q,
        case when p.id = q.acceptedanswerid then 1 else 0 end as is_accepted
    from posts p
    join posts q on q.id = p.parentid and q.posttypeid = 1
    where p.posttypeid = 2
),
badge_rollup as (
    select
        b.userid as user_id,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) as total_badges,
        max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as total_comments,
        coalesce(sum(case when c.score >= 5 then 1 else 0 end), 0) as hi_score_comments,
        max(c.creationdate) as last_comment_at
    from comments c
    group by c.userid
),
vote_agg as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid = 5) as favorites_cast,
        count(*) filter (where v.votetypeid in (8,9)) as bounties_interactions,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total
    from votes v
    group by v.userid
),
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        count(*) as dup_link_count,
        min(pl.creationdate) as first_dup_seen
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
post_closures as (
    select
        ph.postid,
        min(ph.creationdate) as first_closed_at,
        max(ph.creationdate) as last_closed_at,
        string_agg(distinct crt.name, ', ' order by crt.name) as close_reasons
    from posthistory ph
    left join closereasontypes crt
        on ph.posthistorytypeid = 10
       and ph.comment ~ '^[0-9]+$'
       and crt.id = cast(ph.comment as smallint)
    where ph.posthistorytypeid = 10
    group by ph.postid
),
user_posts as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        sum(coalesce(p.score,0)) filter (where p.posttypeid in (1,2)) as qa_score_total,
        max(p.lastactivitydate) as last_post_activity
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
tag_exploded as (
    select
        q.owneruserid as user_id,
        q.id as question_id,
        lower(trim(tg)) as tag_name
    from posts q
    cross join lateral unnest(
        case
            when q.tags is not null and length(q.tags) > 2
                then string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')
            else cast(array[] as text[])
        end
    ) as tg
    where q.posttypeid = 1
),
top_tags as (
    select
        s.user_id,
        string_agg(tag_name, ', ' order by cnt desc, tag_name) as top_5_tags
    from (
        select user_id, tag_name, count(*) as cnt,
               row_number() over (partition by user_id order by count(*) desc, tag_name) as rn
        from tag_exploded
        group by user_id, tag_name
    ) s
    where rn <= 5
    group by s.user_id
),
activity_window as (
    select
        q.user_id,
        q.question_id,
        q.q_created,
        q.q_score,
        q.q_views,
        q.q_favs,
        q.q_answers,
        q.closed_at,
        row_number() over (partition by q.user_id order by q.q_created desc, q.question_id desc) as rn_recent_q,
        avg(q.q_score) over (partition by q.user_id) as avg_q_score_per_user,
        -- replace ordered-set percentile_cont(0.5) within group (order by q.q_score) over (partition by q.user_id)
        -- with an approximate median using percentile_disc via a subquery per user to be portable
        null::numeric as median_q_score_per_user,
        sum(q.q_views) over (partition by q.user_id) as total_views_user
    from question_activity q
),
activity_medians as (
    -- compute median per user using percentile_disc via aggregation (portable approach)
    select
        q.user_id,
        percentile_disc(0.5) within group (order by q.q_score) as median_q_score_per_user
    from question_activity q
    group by q.user_id
),
accepted_answer_ratio as (
    select
        aa.user_id,
        cast(count(*) as numeric) as total_answers,
        cast(sum(case when aa.is_accepted = 1 then 1 else 0 end) as numeric) as accepted_answers,
        case when count(*) = 0 then null else cast(sum(case when aa.is_accepted = 1 then 1 else 0 end) as numeric) / count(*) end as accept_rate
    from answer_activity aa
    group by aa.user_id
),
question_outliers as (
    select
        aw.user_id,
        aw.question_id,
        aw.q_score,
        aw.q_views,
        case
            when aw.q_score >= coalesce(aw.avg_q_score_per_user, 0) * 2 then 1
            when aw.q_score <= coalesce(aw.avg_q_score_per_user, 0) / 2 then -1
            else 0
        end as score_outlier_flag
    from (
        select
            q.*,
            avg(q.q_score) over (partition by q.user_id) as avg_q_score_per_user
        from question_activity q
    ) aw
),
user_quality as (
    select
        u.id as user_id,
        coalesce(a.ar, 0) as answers_recent,
        coalesce(qr.qr, 0) as questions_recent,
        case
            when coalesce(a.ar, 0) + coalesce(qr.qr, 0) = 0 then null
            else round(100.0 * coalesce(a.ar, 0) / cast((coalesce(a.ar, 0) + coalesce(qr.qr, 0)) as numeric), 2)
        end as pct_answers_recent
    from users u
    left join (
        select owneruserid as user_id, count(*) as ar
        from posts
        where posttypeid = 2
          and creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
        group by owneruserid
    ) a on a.user_id = u.id
    left join (
        select owneruserid as user_id, count(*) as qr
        from posts
        where posttypeid = 1
          and creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
        group by owneruserid
    ) qr on qr.user_id = u.id
),
hot_network as (
    select
        distinct ph.postid as question_id,
        min(ph.creationdate) over (partition by ph.postid) as first_hot_at
    from posthistory ph
    where ph.posthistorytypeid = 52
),
final_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.websiteurl,
        ru.rn_newest,
        ru.rep_decile,
        up.questions,
        up.answers,
        up.qa_score_total,
        up.last_post_activity,
        ba.gold_badges,
        ba.silver_badges,
        ba.bronze_badges,
        ba.total_badges,
        ba.last_badge_at,
        cs.total_comments,
        cs.hi_score_comments,
        cs.last_comment_at,
        va.upvotes_cast,
        va.downvotes_cast,
        va.favorites_cast,
        va.bounties_interactions,
        va.bounty_amount_total,
        ar.total_answers,
        ar.accepted_answers,
        ar.accept_rate,
        uq.pct_answers_recent,
        tt.top_5_tags
    from recent_users ru
    left join user_posts up on up.user_id = ru.user_id
    left join badge_rollup ba on ba.user_id = ru.user_id
    left join comment_stats cs on cs.user_id = ru.user_id
    left join vote_agg va on va.user_id = ru.user_id
    left join accepted_answer_ratio ar on ar.user_id = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
    left join top_tags tt on tt.user_id = ru.user_id
),
question_enriched as (
    select
        q.user_id,
        q.question_id,
        q.q_created,
        q.q_score,
        q.q_views,
        q.q_favs,
        q.q_answers,
        q.closed_at,
        coalesce(aw.avg_q_score_per_user, aw2.avg_q_score_per_user) as avg_q_score_per_user,
        am.median_q_score_per_user,
        coalesce(aw.total_views_user, 0) as total_views_user,
        qo.score_outlier_flag,
        case when pc.postid is not null then 1 else 0 end as was_closed,
        pc.first_closed_at,
        pc.close_reasons,
        case when hl.question_id is not null then 1 else 0 end as was_hot,
        hl.first_hot_at,
        coalesce(dl.dup_link_count, 0) as dup_link_count,
        dl.first_dup_seen
    from question_activity q
    left join (
        select
            q.user_id,
            q.question_id,
            avg(q.q_score) over (partition by q.user_id) as avg_q_score_per_user,
            sum(q.q_views) over (partition by q.user_id) as total_views_user
        from question_activity q
    ) aw on aw.user_id = q.user_id and aw.question_id = q.question_id
    left join (
        select user_id, avg(q_score) as avg_q_score_per_user
        from question_activity
        group by user_id
    ) aw2 on aw2.user_id = q.user_id
    left join activity_medians am on am.user_id = q.user_id
    left join question_outliers qo
      on qo.user_id = q.user_id and qo.question_id = q.question_id
    left join post_closures pc
      on pc.postid = q.question_id
    left join hot_network hl
      on hl.question_id = q.question_id
    left join dup_links dl
      on dl.dup_post_id = q.question_id
),
ranked_questions as (
    select
        qe.user_id,
        qe.question_id,
        qe.q_created,
        qe.q_score,
        qe.q_views,
        qe.q_favs,
        qe.q_answers,
        qe.closed_at,
        qe.avg_q_score_per_user,
        qe.median_q_score_per_user,
        qe.total_views_user,
        qe.score_outlier_flag,
        qe.was_closed,
        qe.first_closed_at,
        qe.close_reasons,
        qe.was_hot,
        qe.first_hot_at,
        qe.dup_link_count,
        qe.first_dup_seen,
        row_number() over (partition by qe.user_id order by
            coalesce(qe.q_score, -9999) desc,
            coalesce(qe.q_views, -9999) desc,
            qe.question_id desc) as rn_best_q,
        row_number() over (partition by qe.user_id order by
            qe.q_created desc, qe.question_id desc) as rn_latest_q
    from question_enriched qe
),
correlated_metrics as (
    select
        fu.user_id,
        (
            select count(*) from posts p
            where p.posttypeid = 2
              and p.owneruserid = fu.user_id
              and p.creationdate >= fu.creationdate
        ) as answers_since_join,
        (
            select avg(sub.score)
            from posts sub
            where sub.posttypeid = 2
              and sub.owneruserid = fu.user_id
        ) as avg_answer_score,
        (
            select max(ph.creationdate)
            from posthistory ph
            where ph.userid = fu.user_id
        ) as last_any_edit_at
    from final_users fu
)
select
    fu.user_id,
    fu.displayname,
    fu.reputation,
    fu.rep_decile,
    fu.creationdate,
    coalesce(nullif(fu.location, ''), 'Unknown') as location,
    fu.websiteurl,
    fu.questions,
    fu.answers,
    fu.qa_score_total,
    fu.total_badges,
    fu.gold_badges,
    fu.silver_badges,
    fu.bronze_badges,
    fu.upvotes_cast,
    fu.downvotes_cast,
    fu.favorites_cast,
    fu.bounties_interactions,
    fu.bounty_amount_total,
    fu.total_comments,
    fu.hi_score_comments,
    fu.accept_rate,
    fu.pct_answers_recent,
    coalesce(fu.top_5_tags, '(none)') as top_tags,
    cm.answers_since_join,
    cm.avg_answer_score,
    cm.last_any_edit_at,
    rq_best.question_id as best_question_id,
    rq_best.q_score as best_q_score,
    rq_best.q_views as best_q_views,
    rq_best.q_favs as best_q_favs,
    rq_best.q_answers as best_q_answers,
    rq_best.was_hot as best_q_was_hot,
    rq_best.was_closed as best_q_was_closed,
    rq_best.close_reasons as best_q_close_reasons,
    rq_latest.question_id as latest_question_id,
    rq_latest.q_created as latest_q_created,
    rq_latest.score_outlier_flag as latest_q_outlier_flag,
    rq_latest.dup_link_count as latest_q_dup_link_count,
    case
        when fu.reputation >= 10000 then 'Legend'
        when fu.reputation >= 5000 then 'Expert'
        when fu.reputation >= 1000 then 'Contributor'
        when fu.reputation >= 100 then 'Participant'
        else 'Newbie'
    end as user_tier,
    case
        when coalesce(fu.answers,0) > coalesce(fu.questions,0) then 'Answer-leaning'
        when coalesce(fu.answers,0) < coalesce(fu.questions,0) then 'Question-leaning'
        when coalesce(fu.answers,0) = 0 and coalesce(fu.questions,0) = 0 then 'Silent'
        else 'Balanced'
    end as participation_profile
from final_users fu
left join ranked_questions rq_best
  on rq_best.user_id = fu.user_id and rq_best.rn_best_q = 1
left join ranked_questions rq_latest
  on rq_latest.user_id = fu.user_id and rq_latest.rn_latest_q = 1
left join correlated_metrics cm
  on cm.user_id = fu.user_id
where
    (fu.rep_decile in (1, 10) or coalesce(fu.accept_rate, 0) < 0.2 or coalesce(fu.gold_badges,0) >= 1)
  and (
    exists (
        select 1
        from posts px
        where px.owneruserid = fu.user_id
          and px.posttypeid in (1,2)
          and px.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
    )
    or coalesce(fu.total_badges, 0) >= 10
  )
order by
    fu.rep_decile asc,
    fu.reputation desc NULLS LAST,
    fu.user_id
limit 250;