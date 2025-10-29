with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        date_trunc('month', u.creationdate) as cohort_month,
        coalesce(nullif(trim(lower(u.location)), ''), 'unknown') as norm_location
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
user_badges as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_posts as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        p.favoritecount,
        p.closeddate,
        p.communityowneddate
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select
        p.id as post_id,
        p.parentid as question_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score
    from posts p
    where p.posttypeid = 2
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount, 0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount, 0) else 0 end) as bounty_awarded,
        count(*) as total_votes,
        max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
comment_stats as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.score) as max_comment_score,
        max(c.creationdate) as last_comment_at
    from comments c
    group by c.postid
),
close_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_at,
        max(ph.creationdate) as last_close_at,
        count(case when ph.posthistorytypeid = 10 then 1 end) as close_events,
        count(case when ph.posthistorytypeid = 11 then 1 end) as reopen_events,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_code
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
dup_links as (
    select
        pl.postid as dup_post_id,
        count(case when pl.linktypeid = 3 then 1 end) as duplicate_links,
        count(case when pl.linktypeid = 1 then 1 end) as related_links,
        max(pl.creationdate) as last_link_at
    from postlinks pl
    group by pl.postid
),
tag_expansion as (
    select
        qp.post_id,
        unnest(string_to_array(substring(qp.tags, 2, greatest(length(qp.tags)-2,0)), '><')) as tagname
    from question_posts qp
    where qp.tags is not null
),
tag_density as (
    select
        te.post_id,
        count(*) as tag_count,
        string_agg(te.tagname, ',' order by te.tagname) as tag_list
    from tag_expansion te
    group by te.post_id
),
answers_by_question as (
    select
        ap.question_id,
        count(*) as total_answers,
        avg(cast(ap.score as numeric)) as avg_answer_score,
        max(ap.score) as max_answer_score,
        min(ap.creationdate) as first_answer_at,
        max(ap.creationdate) as last_answer_at
    from answer_posts ap
    group by ap.question_id
),
accepted_answers as (
    select
        q.id as question_id,
        q.acceptedanswerid as accepted_id,
        aa.score as accepted_score,
        aa.creationdate as accepted_created_at
    from posts q
    left join posts aa on aa.id = q.acceptedanswerid
    where q.posttypeid = 1
),
user_activity as (
    select
        ru.user_id,
        count(case when qp.post_id is not null then 1 end) as questions_posted,
        count(case when ap.post_id is not null then 1 end) as answers_posted,
        coalesce(sum(greatest(qp.score,0)),0) as q_nonneg_score_sum,
        coalesce(sum(greatest(ap.score,0)),0) as a_nonneg_score_sum,
        max(coalesce(qp.creationdate, ap.creationdate)) as last_post_at
    from recent_users ru
    left join question_posts qp on qp.user_id = ru.user_id
    left join answer_posts ap on ap.user_id = ru.user_id
    group by ru.user_id
),
question_quality as (
    select
        qp.post_id,
        qp.user_id,
        qp.creationdate,
        qp.score,
        qp.viewcount,
        qp.answercount,
        qp.favoritecount,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(cs.comment_count,0) as comment_count,
        coalesce(td.tag_count,0) as tag_count,
        coalesce(abq.total_answers,0) as total_answers,
        abq.avg_answer_score,
        abq.max_answer_score,
        case when qp.closeddate is not null then 1 else 0 end as is_closed,
        case when qp.communityowneddate is not null then 1 else 0 end as is_community,
        coalesce(cl.close_events,0) as close_events,
        coalesce(cl.reopen_events,0) as reopen_events,
        coalesce(dl.duplicate_links,0) as duplicate_links,
        coalesce(dl.related_links,0) as related_links,
        coalesce(va.bounty_started,0) as bounty_started,
        coalesce(va.bounty_awarded,0) as bounty_awarded
    from question_posts qp
    left join votes_agg va on va.postid = qp.post_id
    left join comment_stats cs on cs.postid = qp.post_id
    left join tag_density td on td.post_id = qp.post_id
    left join answers_by_question abq on abq.question_id = qp.post_id
    left join close_events cl on cl.postid = qp.post_id
    left join dup_links dl on dl.dup_post_id = qp.post_id
),
score_ranks as (
    select
        qq.post_id,
        qq.user_id,
        qq.creationdate,
        qq.score,
        qq.viewcount,
        qq.answercount,
        qq.favoritecount,
        qq.upvotes,
        qq.downvotes,
        qq.comment_count,
        qq.tag_count,
        qq.total_answers,
        qq.avg_answer_score,
        qq.max_answer_score,
        qq.is_closed,
        qq.is_community,
        qq.close_events,
        qq.reopen_events,
        qq.duplicate_links,
        qq.related_links,
        qq.bounty_started,
        qq.bounty_awarded,
        row_number() over (partition by date_trunc('month', qq.creationdate) order by qq.score desc nulls last) as rn_month_score,
        percent_rank() over (partition by date_trunc('month', qq.creationdate) order by qq.viewcount desc nulls last) as pr_month_views,
        dense_rank() over (order by qq.score desc nulls last) as global_score_rank,
        ntile(10) over (order by coalesce(qq.upvotes - qq.downvotes,0) desc) as decile_net_votes
    from question_quality qq
),
user_enriched as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.cohort_month,
        ru.norm_location,
        ua.questions_posted,
        ua.answers_posted,
        ua.q_nonneg_score_sum,
        ua.a_nonneg_score_sum,
        ua.last_post_at,
        ub.total_badges,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        ub.last_badge_date
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badges ub on ub.userid = ru.user_id
),
final_scores as (
    select
        sr.post_id,
        sr.user_id,
        sr.creationdate,
        sr.score,
        sr.viewcount,
        sr.answercount,
        sr.favoritecount,
        sr.upvotes,
        sr.downvotes,
        sr.comment_count,
        sr.tag_count,
        sr.total_answers,
        sr.avg_answer_score,
        sr.max_answer_score,
        sr.is_closed,
        sr.is_community,
        sr.close_events,
        sr.reopen_events,
        sr.duplicate_links,
        sr.related_links,
        sr.bounty_started,
        sr.bounty_awarded,
        sr.rn_month_score,
        sr.pr_month_views,
        sr.global_score_rank,
        sr.decile_net_votes,
        ue.displayname,
        ue.reputation,
        ue.cohort_month,
        ue.norm_location,
        ue.questions_posted,
        ue.answers_posted,
        ue.total_badges,
        round(
            cast(
                coalesce(sr.score,0) * 2.0
                + coalesce(sr.upvotes,0) * 1.0
                - coalesce(sr.downvotes,0) * 1.5
                + ln(greatest(sr.viewcount,1)) * 1.2
                + coalesce(sr.favoritecount,0) * 1.3
                + coalesce(sr.total_answers,0) * 0.8
                + coalesce(sr.avg_answer_score,0) * 0.5
                + case when sr.is_closed = 1 then -5 else 0 end
                + case when sr.duplicate_links > 0 then -3 else 0 end
                + case when sr.bounty_awarded > 0 then 2 else 0 end
                + least(coalesce(ue.reputation,0) / 1000.0, 10)
            as numeric), 3) as quality_score
    from score_ranks sr
    left join user_enriched ue on ue.user_id = sr.user_id
),
cohort_stats as (
    select
        fs.cohort_month,
        count(*) as q_count,
        avg(fs.quality_score) as avg_quality,
        percentile_cont(0.9) within group (order by fs.quality_score) as p90_quality,
        count(case when fs.is_closed = 1 then 1 end) as closed_count,
        count(case when fs.duplicate_links > 0 then 1 end) as dup_count
    from final_scores fs
    group by fs.cohort_month
),
location_stats as (
    select
        fs.norm_location,
        count(*) as q_count,
        avg(fs.quality_score) as avg_quality,
        sum(fs.favoritecount) as favs_sum,
        sum(fs.viewcount) as views_sum
    from final_scores fs
    group by fs.norm_location
),
mixed_set_pre as (
    select
        'top_quality' as src,
        fs.post_id,
        fs.user_id,
        fs.quality_score,
        fs.global_score_rank as rank_val
    from final_scores fs
    where fs.global_score_rank <= 100
    union all
    select
        'most_viewed' as src,
        fs.post_id,
        fs.user_id,
        fs.quality_score,
        dense_rank() over (order by fs.viewcount desc nulls last) as rank_val
    from final_scores fs
),
mixed_set as (
    select m.*
    from mixed_set_pre m
    where not (m.src = 'most_viewed' and m.rank_val > 100)
),
user_corr as (
    select
        fs.user_id,
        corr(fs.quality_score, cast(fs.viewcount as numeric)) as corr_quality_views,
        corr(fs.quality_score, cast(coalesce(fs.upvotes - fs.downvotes,0) as numeric)) as corr_quality_netvotes
    from final_scores fs
    group by fs.user_id
)
select
    fs.post_id,
    fs.user_id,
    fs.displayname,
    fs.reputation,
    fs.cohort_month,
    fs.norm_location,
    fs.score,
    fs.viewcount,
    fs.answercount,
    fs.favoritecount,
    fs.upvotes,
    fs.downvotes,
    fs.comment_count,
    fs.tag_count,
    fs.total_answers,
    fs.avg_answer_score,
    fs.max_answer_score,
    fs.is_closed,
    fs.is_community,
    fs.close_events,
    fs.reopen_events,
    fs.duplicate_links,
    fs.related_links,
    fs.bounty_started,
    fs.bounty_awarded,
    fs.rn_month_score,
    fs.pr_month_views,
    fs.global_score_rank,
    fs.decile_net_votes,
    fs.quality_score,
    cs.avg_quality as cohort_avg_quality,
    ls.avg_quality as location_avg_quality,
    coalesce(uc.corr_quality_views, 0) as user_corr_quality_views,
    coalesce(uc.corr_quality_netvotes, 0) as user_corr_quality_netvotes,
    ms.src as surfaced_by,
    ms.rank_val as surfaced_rank,
    coalesce(nullif(trim(fs.displayname), ''), '(anonymous)') || ' [' ||
      coalesce(fs.norm_location, 'n/a') || ']' as display_with_loc,
    case
        when fs.tag_count is null or fs.tag_count = 0 then 'untagged'
        when fs.tag_count = 1 then 'single-tag'
        when fs.tag_count between 2 and 5 then 'multi-tag'
        else 'heavy-tag'
    end as tag_profile
from final_scores fs
left join cohort_stats cs on cs.cohort_month = fs.cohort_month
left join location_stats ls on ls.norm_location = fs.norm_location
left join mixed_set ms on ms.post_id = fs.post_id
left join user_corr uc on uc.user_id = fs.user_id
where
    fs.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    and (fs.score >= 0 or fs.viewcount > 100)
    and (
        fs.is_closed = 0
        or (fs.is_closed = 1 and fs.reopen_events > 0)
    )
    and (
        fs.norm_location not ilike '%test%'
        or fs.norm_location is null
    )
    and (
        position('python' in coalesce((select td.tag_list from tag_density td where td.post_id = fs.post_id), '')) > 0
        or fs.favoritecount >= 5
    )
order by
    fs.quality_score desc nulls last,
    fs.viewcount desc nulls last
limit 500;