-- {"query": "46.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3379}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
        dense_rank() over (order by u.creationdate desc) as recency_rank
    from users u
),
q_posts as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        p.closeddate,
        p.communityowneddate
    from posts p
    where p.posttypeid = 1
),
a_posts as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as user_id,
        a.creationdate as answer_creation,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
first_answer as (
    select
        question_id,
        min(answer_creation) as first_answer_time
    from a_posts
    group by question_id
),
answer_stats as (
    select
        ap.question_id,
        count(*) as answers_total,
        avg(ap.answer_score) as avg_answer_score,
        sum(case when ap.answer_score > 0 then 1 else 0 end) as pos_answers
    from a_posts ap
    group by ap.question_id
),
q_with_answers as (
    select
        q.post_id,
        q.user_id,
        q.creationdate as q_creation,
        q.score as q_score,
        q.viewcount as q_views,
        q.title,
        q.tags,
        q.answercount,
        fa.first_answer_time,
        extract(epoch from (fa.first_answer_time - q.creationdate)) as secs_to_first_answer,
        coalesce(ans.answers_total, 0) as answers_total,
        ans.avg_answer_score,
        ans.pos_answers
    from q_posts q
    left join first_answer fa on fa.question_id = q.post_id
    left join answer_stats ans on ans.question_id = q.post_id
),
tag_expanded as (
    select
        qwa.post_id,
        unnest(string_to_array(substring(qwa.tags from 2 for length(qwa.tags)-2), '><')) as tagname
    from q_with_answers qwa
    where qwa.tags is not null
),
tag_quality as (
    select
        te.tagname,
        count(distinct te.post_id) as questions_with_tag,
        avg(qwa.q_score) as avg_q_score,
        percentile_cont(0.5) within group (order by qwa.q_views) as median_q_views,
        avg(qwa.secs_to_first_answer) filter (where qwa.secs_to_first_answer is not null) as avg_secs_to_first_answer
    from tag_expanded te
    join q_with_answers qwa on qwa.post_id = te.post_id
    group by te.tagname
),
post_votes as (
    select
        v.postid,
        sum(case when vt.name = 'UpMod' then 1 else 0 end) as upvotes,
        sum(case when vt.name = 'DownMod' then 1 else 0 end) as downvotes,
        sum(case when vt.name = 'Favorite' then 1 else 0 end) as favorites,
        sum(case when vt.name = 'BountyStart' then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when vt.name = 'BountyClose' then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    join votetypes vt on vt.id = v.votetypeid
    group by v.postid
),
post_links as (
    select
        pl.postid,
        sum(case when lt.name = 'Linked' then 1 else 0 end) as links_out,
        sum(case when lt.name = 'Duplicate' then 1 else 0 end) as duplicates_of
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid
    group by pl.postid
),
close_events as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_date,
        max(case when ph.posthistorytypeid = 10 then (case when ph.comment ~ '^[0-9]+$' then cast(ph.comment as integer) else null end) else null end) as last_close_reason_id
    from posthistory ph
    group by ph.postid
),
close_reason_names as (
    select
        crt.id,
        crt.name
    from closereasontypes crt
),
user_badge_stats as (
    select
        b.userid,
        count(*) as badges_total,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.tagbased = true then 1 else 0 end) as tag_badges
    from badges b
    group by b.userid
),
user_activity as (
    select
        u.id as user_id,
        count(distinct q.id) filter (where q.posttypeid = 1) as q_count,
        count(distinct a.id) filter (where a.posttypeid = 2) as a_count,
        avg(q.score) filter (where q.posttypeid = 1) as avg_q_score,
        avg(a.score) filter (where a.posttypeid = 2) as avg_a_score
    from users u
    left join posts q on q.owneruserid = u.id and q.posttypeid = 1
    left join posts a on a.owneruserid = u.id and a.posttypeid = 2
    group by u.id
),
comment_aggs as (
    select
        c.postid,
        count(*) as comments_count,
        avg(c.score) as avg_comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
question_enriched as (
    select
        qwa.*,
        pv.upvotes,
        pv.downvotes,
        pv.favorites,
        pv.bounty_started,
        pv.bounty_awarded,
        pl.links_out,
        pl.duplicates_of,
        ce.first_close_date,
        ce.last_reopen_date,
        crn.name as close_reason_name,
        ca.comments_count,
        ca.avg_comment_score,
        ca.last_comment_date
    from q_with_answers qwa
    left join post_votes pv on pv.postid = qwa.post_id
    left join post_links pl on pl.postid = qwa.post_id
    left join close_events ce on ce.postid = qwa.post_id
    left join close_reason_names crn on crn.id = ce.last_close_reason_id
    left join comment_aggs ca on ca.postid = qwa.post_id
),
user_enriched as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.websiteurl_norm,
        ru.recency_rank,
        coalesce(ub.badges_total,0) as badges_total,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        coalesce(ub.tag_badges,0) as tag_badges,
        coalesce(ua.q_count,0) as q_count,
        coalesce(ua.a_count,0) as a_count,
        ua.avg_q_score,
        ua.avg_a_score
    from recent_users ru
    left join user_badge_stats ub on ub.userid = ru.user_id
    left join user_activity ua on ua.user_id = ru.user_id
),
user_question_rollup as (
    select
        ue.user_id,
        count(qe.post_id) as questions_asked,
        avg(qe.q_score) as avg_q_score,
        avg(qe.q_views) as avg_q_views,
        avg(qe.answers_total) as avg_answers_total,
        avg(qe.secs_to_first_answer) as avg_secs_to_first_answer,
        sum(coalesce(qe.favorites,0)) as sum_favorites,
        sum(coalesce(qe.upvotes,0)) as sum_upvotes,
        sum(coalesce(qe.downvotes,0)) as sum_downvotes,
        sum(coalesce(qe.bounty_awarded,0)) as sum_bounty_awarded
    from user_enriched ue
    left join question_enriched qe on qe.user_id = ue.user_id
    group by ue.user_id
),
ranked_questions as (
    select
        qe.post_id,
        qe.user_id,
        qe.q_creation,
        qe.q_score,
        qe.q_views,
        qe.title,
        qe.answers_total,
        qe.secs_to_first_answer,
        qe.favorites,
        qe.upvotes,
        qe.downvotes,
        qe.bounty_awarded,
        row_number() over (partition by qe.user_id order by coalesce(qe.q_score, -2147483648) desc, qe.q_views desc) as rn_best_by_score,
        row_number() over (partition by qe.user_id order by qe.q_creation desc) as rn_most_recent
    from question_enriched qe
),
best_and_recent as (
    select
        rq.user_id,
        max(case when rq.rn_best_by_score = 1 then rq.post_id end) as best_q_id,
        max(case when rq.rn_best_by_score = 1 then rq.title end) as best_q_title,
        max(case when rq.rn_best_by_score = 1 then rq.q_score end) as best_q_score,
        max(case when rq.rn_most_recent = 1 then rq.post_id end) as recent_q_id,
        max(case when rq.rn_most_recent = 1 then rq.title end) as recent_q_title,
        max(case when rq.rn_most_recent = 1 then rq.q_creation end) as recent_q_creation
    from ranked_questions rq
    group by rq.user_id
),
power_tags as (
    select
        tq.tagname,
        tq.questions_with_tag,
        tq.avg_q_score,
        tq.median_q_views,
        tq.avg_secs_to_first_answer,
        ntile(4) over (order by tq.avg_q_score) as score_quartile
    from tag_quality tq
    where tq.questions_with_tag >= 10
),
tag_picks as (
    select distinct on (pt.score_quartile)
        pt.score_quartile,
        pt.tagname,
        pt.questions_with_tag,
        pt.avg_q_score,
        pt.median_q_views
    from power_tags pt
    order by pt.score_quartile, coalesce(pt.avg_q_score, -1000000000) desc, pt.median_q_views desc
),
user_top_tag as (
    select
        teq.user_id,
        teq.tagname,
        count(*) as tag_q_count,
        row_number() over (partition by teq.user_id order by count(*) desc, min(teq.post_id)) as rn
    from (
        select qe.user_id, te.tagname, te.post_id
        from question_enriched qe
        join tag_expanded te on te.post_id = qe.post_id
    ) teq
    group by teq.user_id, teq.tagname
),
final_users as (
    select
        ue.user_id,
        ue.displayname,
        ue.reputation,
        ue.creationdate,
        ue.location,
        ue.websiteurl_norm,
        ue.recency_rank,
        ue.badges_total,
        ue.gold_badges,
        ue.silver_badges,
        ue.bronze_badges,
        ue.tag_badges,
        ue.q_count,
        ue.a_count,
        ue.avg_q_score,
        ue.avg_a_score,
        uqr.questions_asked,
        uqr.avg_q_score as user_avg_q_score,
        uqr.avg_q_views as user_avg_q_views,
        uqr.avg_answers_total as user_avg_answers_total,
        uqr.avg_secs_to_first_answer as user_avg_secs_to_first_answer,
        uqr.sum_favorites,
        uqr.sum_upvotes,
        uqr.sum_downvotes,
        uqr.sum_bounty_awarded,
        bar.best_q_id,
        bar.best_q_title,
        bar.best_q_score,
        bar.recent_q_id,
        bar.recent_q_title,
        bar.recent_q_creation,
        utt.tagname as top_tag
    from user_enriched ue
    left join user_question_rollup uqr on uqr.user_id = ue.user_id
    left join best_and_recent bar on bar.user_id = ue.user_id
    left join user_top_tag utt on utt.user_id = ue.user_id and utt.rn = 1
)
select
    fu.user_id,
    fu.displayname,
    fu.reputation,
    fu.location,
    fu.websiteurl_norm,
    fu.recency_rank,
    fu.badges_total,
    fu.gold_badges,
    fu.silver_badges,
    fu.bronze_badges,
    fu.tag_badges,
    fu.q_count,
    fu.a_count,
    round(coalesce(fu.user_avg_q_score, fu.avg_q_score), 2) as avg_q_score,
    round(coalesce(fu.user_avg_q_views, 0), 2) as avg_q_views,
    round(coalesce(fu.user_avg_answers_total, 0), 2) as avg_answers_total,
    round(coalesce(fu.user_avg_secs_to_first_answer, 0), 2) as avg_secs_to_first_answer,
    fu.sum_favorites,
    fu.sum_upvotes,
    fu.sum_downvotes,
    fu.sum_bounty_awarded,
    fu.best_q_id,
    fu.best_q_title,
    fu.best_q_score,
    fu.recent_q_id,
    fu.recent_q_title,
    fu.recent_q_creation,
    fu.top_tag,
    tp.tagname as quartile_top_tagname,
    tp.score_quartile as tag_score_quartile,
    tp.questions_with_tag as quartile_tag_questions,
    tp.avg_q_score as quartile_tag_avg_q_score,
    tp.median_q_views as quartile_tag_median_views,
    case
        when fu.sum_upvotes is null and fu.sum_downvotes is null then 'no-vote-activity'
        when coalesce(fu.sum_upvotes,0) + coalesce(fu.sum_downvotes,0) = 0 then 'no-votes'
        when coalesce(fu.sum_upvotes,0) >= 5 * coalesce(fu.sum_downvotes,0) then 'well-received'
        when coalesce(fu.sum_downvotes,0) > coalesce(fu.sum_upvotes,0) then 'controversial'
        else 'mixed'
    end as vote_profile,
    case
        when fu.questions_asked is null then 'lurker'
        when fu.questions_asked = 0 and fu.a_count > 0 then 'answerer-only'
        when fu.questions_asked > 0 and fu.a_count = 0 then 'asker-only'
        when fu.questions_asked > 0 and fu.a_count > 0 then 'hybrid'
        else 'other'
    end as participation_profile
from final_users fu
left join tag_picks tp
    on tp.score_quartile = ((fu.reputation % 4) + 1)
where
    coalesce(fu.displayname, '') not ilike '%bot%'
    and (fu.websiteurl_norm is null or fu.websiteurl_norm not ilike '%stackexchange.com%')
    and (
        fu.recency_rank <= 500
        or (fu.reputation > 10000 and coalesce(fu.questions_asked,0) + coalesce(fu.a_count,0) > 50)
    )
order by
    fu.reputation desc,
    coalesce(fu.sum_upvotes,0) - coalesce(fu.sum_downvotes,0) desc,
    fu.user_id
limit 250;