with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.upvotes,
        u.downvotes,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_recent
    from users u
    where u.creationdate >= (select coalesce(max(creationdate), (timestamp '2024-10-01 12:34:56') - interval '10 years') from users) - interval '365 days'
),
question_posts as (
    select
        p.id as post_id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.answercount,
        p.commentcount
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answer_owner_id,
        a.score as answer_score,
        a.creationdate as answer_creationdate
    from posts a
    where a.posttypeid = 2
),
user_activity as (
    select
        u.user_id,
        count(distinct qp.post_id) filter (where qp.post_id is not null) as questions_asked,
        count(distinct ap.answer_id) filter (where ap.answer_id is not null) as answers_posted,
        sum(qp.viewcount) as total_views_on_questions,
        sum(qp.score) as total_question_score,
        sum(ap.answer_score) as total_answer_score,
        sum(case when qp.acceptedanswerid is not null then 1 else 0 end) as questions_with_accept,
        max(qp.creationdate) as last_question_date,
        max(ap.answer_creationdate) as last_answer_date
    from recent_users u
    left join question_posts qp on qp.owneruserid = u.user_id
    left join answer_posts ap on ap.answer_owner_id = u.user_id
    group by u.user_id
),
tag_unpivot as (
    select
        q.post_id,
        unnest(string_to_array(coalesce(substring(q.tags, 2, length(q.tags)-2), ''), '><')) as tag
    from question_posts q
),
top_tags as (
    select
        t.tag,
        count(*) as tag_usage,
        percentile_disc(0.9) within group (order by q.viewcount) as p90_views_for_tag
    from tag_unpivot t
    join question_posts q on q.post_id = t.post_id
    group by t.tag
    having count(*) > 10
),
vote_agg as (
    select
        v.postid,
        sum(case when vt.name ilike 'UpMod%' then 1 else 0 end) as upvotes,
        sum(case when vt.name ilike 'DownMod%' then 1 else 0 end) as downvotes,
        sum(case when vt.name ilike 'Favorite%' then 1 else 0 end) as favorites,
        sum(case when vt.name ilike 'BountyClose%' then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    join votetypes vt on vt.id = v.votetypeid
    group by v.postid
),
duplicate_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        pl.creationdate as link_created
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid
    where lt.name ilike 'Duplicate%'
),
close_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_date,
        max(ph.creationdate) as last_close_date,
        max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as reopened_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_count,
        cast(max((regexp_match(coalesce(ph.comment,''), '([0-9]+)'))[1]) as int) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
accepted_pairs as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.acceptedanswerid,
        a.owneruserid as answerer_id,
        a.score as accepted_answer_score
    from posts q
    left join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
),
badge_summary as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(*) filter (where b.tagbased = true) as tag_badges
    from badges b
    group by b.userid
),
comment_sentiment as (
    select
        c.postid,
        avg(c.score) as avg_comment_score,
        count(*) as comment_count,
        sum(case when c.text ~* '(thank|great|helpful|awesome|works)' then 1 else 0 end) as positive_hint,
        sum(case when c.text ~* '(wrong|broken|doesn''t|error|fail)' then 1 else 0 end) as negative_hint
    from comments c
    group by c.postid
),
post_quality as (
    select
        q.post_id,
        q.owneruserid,
        coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as net_votes,
        coalesce(va.favorites,0) as favorites,
        coalesce(va.bounty_awarded,0) as bounty_awarded,
        coalesce(cs.avg_comment_score,0) as avg_comment_score,
        coalesce(cs.comment_count,0) as comment_count,
        case
            when q.viewcount is null or q.viewcount = 0 then null
            else round(((q.score)::numeric + coalesce(va.upvotes,0) - coalesce(va.downvotes,0) + coalesce(va.favorites,0) * 0.5) / nullif(q.viewcount,0), 6)
        end as engagement_ratio,
        case when ce.first_close_date is not null then 1 else 0 end as was_closed,
        ce.last_close_reason_id,
        case when dl.original_post_id is not null then 1 else 0 end as is_duplicate,
        q.creationdate,
        q.title
    from question_posts q
    left join vote_agg va on va.postid = q.post_id
    left join comment_sentiment cs on cs.postid = q.post_id
    left join close_events ce on ce.postid = q.post_id
    left join duplicate_links dl on dl.dup_post_id = q.post_id
),
user_rank as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.cohort_month,
        ua.questions_asked,
        ua.answers_posted,
        ua.total_views_on_questions,
        ua.total_question_score,
        ua.total_answer_score,
        ua.questions_with_accept,
        bs.total_badges,
        bs.gold_badges,
        bs.silver_badges,
        bs.bronze_badges,
        bs.tag_badges,
        rank() over (order by coalesce(ua.total_question_score,0) + coalesce(ua.total_answer_score,0) + coalesce(bs.total_badges,0) desc, u.reputation desc, u.user_id) as activity_rank,
        dense_rank() over (partition by date_trunc('quarter', u.creationdate) order by u.reputation desc) as cohort_quarter_rank
    from recent_users u
    left join user_activity ua on ua.user_id = u.user_id
    left join badge_summary bs on bs.userid = u.user_id
),
tag_engagement as (
    select
        t.tag,
        count(*) as q_count,
        avg(pq.engagement_ratio) as avg_engagement_ratio,
        sum(case when pq.was_closed = 1 then 1 else 0 end) as closed_q,
        sum(case when pq.is_duplicate = 1 then 1 else 0 end) as duplicate_q
    from tag_unpivot t
    join post_quality pq on pq.post_id = t.post_id
    group by t.tag
),
post_with_accept_context as (
    select
        pq.post_id,
        pq.owneruserid as asker_id,
        pq.creationdate as question_date,
        pq.net_votes,
        pq.engagement_ratio,
        ap.acceptedanswerid,
        ap.answerer_id,
        ap.accepted_answer_score,
        case when ap.acceptedanswerid is not null then 1 else 0 end as has_accept
    from post_quality pq
    left join accepted_pairs ap on ap.question_id = pq.post_id
),
user_peer_interactions as (
    select
        pwc.asker_id as user_id,
        count(*) filter (where pwc.has_accept = 1) as accepts_given,
        count(distinct pwc.answerer_id) filter (where pwc.answerer_id is not null) as distinct_accepted_answerers,
        avg(pwc.accepted_answer_score) filter (where pwc.accepted_answer_score is not null) as avg_accepted_answer_score
    from post_with_accept_context pwc
    group by pwc.asker_id
),
final_users as (
    select
        ur.*,
        upi.accepts_given,
        upi.distinct_accepted_answerers,
        upi.avg_accepted_answer_score,
        coalesce(upi.accepts_given,0) + coalesce(ur.questions_with_accept,0) as total_accept_touchpoints
    from user_rank ur
    left join user_peer_interactions upi on upi.user_id = ur.user_id
),
recent_quality_questions as (
    select
        pq.*,
        tt.tag,
        tt.tag_usage,
        tt.p90_views_for_tag
    from post_quality pq
    left join lateral (
        select tg.tag, tg.tag_usage, tg.p90_views_for_tag
        from tag_unpivot tu
        join top_tags tg on tg.tag = tu.tag
        where tu.post_id = pq.post_id
        order by tg.tag_usage desc, tg.tag asc
        limit 1
    ) tt on true
    where pq.creationdate >= (timestamp '2024-10-01 12:34:56') - interval '365 days'
),
aggregated as (
    select
        fu.user_id,
        fu.displayname,
        fu.reputation,
        fu.activity_rank,
        fu.cohort_quarter_rank,
        fu.questions_asked,
        fu.answers_posted,
        fu.total_views_on_questions,
        fu.total_question_score,
        fu.total_answer_score,
        fu.questions_with_accept,
        fu.total_badges,
        fu.gold_badges,
        fu.silver_badges,
        fu.bronze_badges,
        fu.tag_badges,
        fu.accepts_given,
        fu.distinct_accepted_answerers,
        fu.avg_accepted_answer_score,
        fu.total_accept_touchpoints,
        count(distinct rqq.post_id) as recent_questions,
        avg(rqq.engagement_ratio) as avg_recent_engagement,
        max(rqq.net_votes) as max_recent_net_votes,
        min(rqq.net_votes) as min_recent_net_votes,
        max(rqq.p90_views_for_tag) as max_tag_p90_views
    from final_users fu
    left join recent_quality_questions rqq on rqq.owneruserid = fu.user_id
    group by fu.user_id, fu.displayname, fu.reputation, fu.activity_rank, fu.cohort_quarter_rank,
             fu.questions_asked, fu.answers_posted, fu.total_views_on_questions, fu.total_question_score,
             fu.total_answer_score, fu.questions_with_accept, fu.total_badges, fu.gold_badges, fu.silver_badges,
             fu.bronze_badges, fu.tag_badges, fu.accepts_given, fu.distinct_accepted_answerers,
             fu.avg_accepted_answer_score, fu.total_accept_touchpoints
),
flagged_posts as (
    select
        pq.post_id,
        pq.title,
        pq.owneruserid,
        pq.net_votes,
        pq.engagement_ratio,
        pq.was_closed,
        pq.last_close_reason_id,
        pq.is_duplicate,
        pq.creationdate,
        case
            when pq.was_closed = 1 and pq.is_duplicate = 1 then 'ClosedDuplicate'
            when pq.was_closed = 1 then 'Closed'
            when pq.is_duplicate = 1 then 'Duplicate'
            when pq.engagement_ratio is not null and pq.engagement_ratio < 0 then 'LowEngagement'
            when pq.net_votes < 0 then 'NegativeVotes'
            else 'Normal'
        end as quality_flag
    from post_quality pq
),
ranked_flags as (
    select
        fp.*,
        row_number() over (partition by quality_flag order by coalesce(engagement_ratio, -999) asc, net_votes asc, creationdate desc, post_id desc) as flag_rank
    from flagged_posts fp
),
complex_set as (
    select user_id, displayname, activity_rank, 'A' as src
    from aggregated
    where activity_rank <= 100
    union
    select user_id, displayname, activity_rank, 'B' as src
    from aggregated
    where total_badges >= 50
    intersect
    select user_id, displayname, activity_rank, 'B' as src
    from aggregated
    where questions_with_accept >= 5
    except
    select user_id, displayname, activity_rank, 'X' as src
    from aggregated
    where answers_posted = 0
)
select
    a.user_id,
    a.displayname,
    a.reputation,
    a.activity_rank,
    a.cohort_quarter_rank,
    a.questions_asked,
    a.answers_posted,
    a.total_views_on_questions,
    a.total_question_score,
    a.total_answer_score,
    a.questions_with_accept,
    a.total_badges,
    a.gold_badges,
    a.silver_badges,
    a.bronze_badges,
    a.tag_badges,
    a.accepts_given,
    a.distinct_accepted_answerers,
    round(coalesce(a.avg_accepted_answer_score,0)::numeric, 3) as avg_accepted_answer_score,
    a.total_accept_touchpoints,
    a.recent_questions,
    round(coalesce(a.avg_recent_engagement,0)::numeric, 6) as avg_recent_engagement,
    a.max_recent_net_votes,
    a.min_recent_net_votes,
    a.max_tag_p90_views,
    coalesce(cs.src, 'N') as cohort_src,
    count(rf.post_id) filter (where rf.quality_flag <> 'Normal') as flagged_posts_count,
    string_agg(distinct concat(rf.quality_flag, '#', rf.post_id)::text, ', ' order by concat(rf.quality_flag, '#', rf.post_id)) as top_flags_sample
from aggregated a
left join complex_set cs on cs.user_id = a.user_id
left join ranked_flags rf on rf.owneruserid = a.user_id and rf.flag_rank <= 25
group by
    a.user_id, a.displayname, a.reputation, a.activity_rank, a.cohort_quarter_rank,
    a.questions_asked, a.answers_posted, a.total_views_on_questions, a.total_question_score,
    a.total_answer_score, a.questions_with_accept, a.total_badges, a.gold_badges, a.silver_badges,
    a.bronze_badges, a.tag_badges, a.accepts_given, a.distinct_accepted_answerers, a.avg_accepted_answer_score,
    a.total_accept_touchpoints, a.recent_questions, a.avg_recent_engagement, a.max_recent_net_votes,
    a.min_recent_net_votes, a.max_tag_p90_views, cs.src
having
    (a.questions_asked + a.answers_posted) > 0
    and (
        a.activity_rank <= 100
        or a.total_badges >= 25
        or a.avg_recent_engagement is not null
    )
order by
    a.activity_rank asc nulls last,
    a.reputation desc nulls last,
    a.user_id
limit 500;