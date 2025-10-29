-- {"query": "254.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3183} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_recent
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
tagged_questions as (
    select
        p.id as question_id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.favoritecount,
        p.title,
        p.tags,
        string_to_array(substring(p.tags, 2, length(p.tags)-2), '><') as tag_array
    from posts p
    where p.posttypeid = 1
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answer_creation,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
accepted_flags as (
    select
        q.id as question_id,
        case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted
    from posts q
    where q.posttypeid = 1
),
user_badge_rollup as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) as total_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
votes_agg as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 5) as favorites,
        count(*) filter (where v.votetypeid = 8) as bounty_starts,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_amount_sum
    from votes v
    group by v.postid
),
comment_sentiment as (
    select
        c.postid,
        avg(c.score) as avg_comment_score,
        count(*) as comment_count,
        sum(case when position('thanks' in lower(c.text)) > 0 then 1 else 0 end) as thanks_count
    from comments c
    group by c.postid
),
link_dupes as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as related_links
    from postlinks pl
    group by pl.postid
),
post_edits as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_id_text
    from posthistory ph
    group by ph.postid
),
question_quality as (
    select
        q.question_id,
        q.owneruserid as asker_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.answercount,
        q.favoritecount,
        q.title,
        q.tags,
        qa.has_accepted,
        va.upvotes,
        va.downvotes,
        coalesce(va.favorites, 0) as favorites_votes,
        coalesce(va.bounty_amount_sum, 0) as bounty_amount_sum,
        coalesce(cs.avg_comment_score, 0) as avg_comment_score,
        coalesce(cs.comment_count, 0) as comment_count,
        coalesce(cs.thanks_count, 0) as thanks_count,
        coalesce(ld.duplicate_links, 0) as duplicate_links,
        coalesce(ld.related_links, 0) as related_links,
        coalesce(pe.edit_count, 0) as edit_count,
        pe.first_edit_date,
        pe.last_edit_date,
        pe.close_events,
        nullif(pe.last_close_reason_id_text, '') as last_close_reason_id_text,
        case
            when q.viewcount is null or q.viewcount = 0 then null
            else round((coalesce(va.upvotes,0) - coalesce(va.downvotes,0))::numeric / q.viewcount::numeric, 6)
        end as score_per_view,
        case
            when q.answercount is null or q.answercount = 0 then 0
            else coalesce(va.upvotes,0)::numeric / q.answercount::numeric
        end as upvotes_per_answer
    from tagged_questions q
    left join accepted_flags qa on qa.question_id = q.question_id
    left join votes_agg va on va.postid = q.question_id
    left join comment_sentiment cs on cs.postid = q.question_id
    left join link_dupes ld on ld.postid = q.question_id
    left join post_edits pe on pe.postid = q.question_id
),
user_activity as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        ub.total_badges,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        ub.last_badge_date,
        coalesce(sum(case when p.posttypeid = 1 then 1 else 0 end), 0) as q_count,
        coalesce(sum(case when p.posttypeid = 2 then 1 else 0 end), 0) as a_count,
        coalesce(sum(p.score), 0) as total_post_score,
        max(p.lastactivitydate) as last_post_activity,
        percentile_cont(0.5) within group (order by p.score) as median_post_score,
        count(distinct p.id) as total_posts
    from users u
    left join badges ub on ub.userid = u.id
    left join posts p on p.owneruserid = u.id
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location, ub.total_badges, ub.gold_badges, ub.silver_badges, ub.bronze_badges, ub.last_badge_date
),
topic_focus as (
    select
        q.asker_id as user_id,
        unnest(q.tags is not null::int[] || array[]::int[]) as dummy -- force planner work; noop
    from question_quality q
),
accepted_answer_latency as (
    select
        q.question_id,
        q.asker_id,
        q.creationdate as question_creation,
        a.answer_id,
        a.answerer_id,
        a.answer_creation,
        extract(epoch from (a.answer_creation - q.creationdate)) as seconds_to_answer,
        case when q.has_accepted = 1 and q.question_id = (select p.id from posts p where p.acceptedanswerid = a.answer_id limit 1) then 1 else 0 end as is_accepted_answer_match
    from question_quality q
    join answers a on a.question_id = q.question_id
),
recent_hot as (
    select
        q.*,
        row_number() over (order by (coalesce(upvotes,0) - coalesce(downvotes,0)) desc, viewcount desc, favoritecount desc) as rn_hot
    from question_quality q
    where q.creationdate >= (select max(creationdate) - interval '90 days' from posts)
),
dupe_clusters as (
    select
        q.question_id,
        count(*) as cluster_size
    from question_quality q
    join postlinks pl on pl.postid = q.question_id and pl.linktypeid = 3
    group by q.question_id
),
user_question_rank as (
    select
        q.asker_id as user_id,
        q.question_id,
        q.score,
        q.viewcount,
        q.upvotes_per_answer,
        dense_rank() over (partition by q.asker_id order by q.score desc nulls last, q.viewcount desc nulls last, q.question_id) as drank_by_score
    from question_quality q
),
agg_per_user as (
    select
        q.asker_id as user_id,
        count(*) as questions_asked,
        sum(case when q.has_accepted = 1 then 1 else 0 end) as accepted_questions,
        avg(coalesce(q.score,0)) as avg_question_score,
        stddev_pop(coalesce(q.score,0)) as stddev_question_score,
        avg(q.score_per_view) filter (where q.score_per_view is not null) as avg_score_per_view,
        max(q.viewcount) as max_views,
        count(*) filter (where q.close_events > 0) as closed_questions,
        sum(q.duplicate_links) as duplicate_links_total
    from question_quality q
    group by q.asker_id
),
answer_engagement as (
    select
        a.answerer_id as user_id,
        count(*) as answers_given,
        avg(a.answer_score) as avg_answer_score,
        min(a.answer_creation) as first_answer_date,
        max(a.answer_creation) as last_answer_date
    from answers a
    group by a.answerer_id
),
closed_reason_detail as (
    select
        q.question_id,
        max(crt.name) as last_close_reason_name
    from question_quality q
    left join posthistory ph on ph.postid = q.question_id and ph.posthistorytypeid = 10
    left join closerreasontypes crt on crt.id = try_cast(nullif(ph.comment, '') as smallint)
    group by q.question_id
),
final_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ua.q_count,
        ua.a_count,
        ua.total_post_score,
        ua.median_post_score,
        ua.total_posts,
        ua.last_post_activity,
        coalesce(ub.total_badges,0) as total_badges,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        ub.last_badge_date
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badge_rollup ub on ub.userid = ru.user_id
)
select
    fu.user_id,
    fu.displayname,
    fu.reputation,
    fu.creationdate as user_since,
    coalesce(nullif(fu.location, ''), 'Unknown') as location,
    fu.total_badges,
    fu.gold_badges,
    fu.silver_badges,
    fu.bronze_badges,
    fu.q_count,
    fu.a_count,
    fu.total_post_score,
    fu.median_post_score,
    fu.total_posts,
    fu.last_post_activity,
    aq.questions_asked,
    aq.accepted_questions,
    aq.avg_question_score,
    aq.stddev_question_score,
    aq.avg_score_per_view,
    aq.max_views,
    aq.closed_questions,
    aq.duplicate_links_total,
    ae.answers_given,
    ae.avg_answer_score,
    ae.first_answer_date,
    ae.last_answer_date,
    rh.rn_hot as recent_hot_rank,
    dq.cluster_size as dupe_cluster_size,
    uqr.drank_by_score as best_question_rank_within_user,
    left(coalesce(max(case when uqr.drank_by_score = 1 then qq.title end), '(no questions)'), 120) as best_question_title_snippet,
    sum(coalesce(qq.favorites_votes,0)) as total_favorites_votes_on_questions,
    sum(coalesce(qq.bounty_amount_sum,0)) as total_bounty_amount_on_questions,
    avg(coalesce(csl.seconds_to_answer, 0)) filter (where csl.is_accepted_answer_match = 1) as avg_seconds_to_accepted_answer,
    max(crd.last_close_reason_name) as last_close_reason_name,
    string_agg(distinct trim(both '<>' from split_part(qq.tags, '><', 1)), ', ') filter (where qq.tags is not null) as sample_first_tag_mix
from final_users fu
left join agg_per_user aq on aq.user_id = fu.user_id
left join answer_engagement ae on ae.user_id = fu.user_id
left join user_question_rank uqr on uqr.user_id = fu.user_id and uqr.drank_by_score = 1
left join question_quality qq on qq.question_id = uqr.question_id
left join recent_hot rh on rh.question_id = qq.question_id
left join dupe_clusters dq on dq.question_id = qq.question_id
left join accepted_answer_latency csl on csl.question_id = qq.question_id
left join closed_reason_detail crd on crd.question_id = qq.question_id
group by
    fu.user_id, fu.displayname, fu.reputation, fu.creationdate, fu.location,
    fu.total_badges, fu.gold_badges, fu.silver_badges, fu.bronze_badges,
    fu.q_count, fu.a_count, fu.total_post_score, fu.median_post_score, fu.total_posts, fu.last_post_activity,
    aq.questions_asked, aq.accepted_questions, aq.avg_question_score, aq.stddev_question_score, aq.avg_score_per_view, aq.max_views, aq.closed_questions, aq.duplicate_links_total,
    ae.answers_given, ae.avg_answer_score, ae.first_answer_date, ae.last_answer_date,
    rh.rn_hot, dq.cluster_size, uqr.drank_by_score
having
    coalesce(aq.questions_asked, 0) + coalesce(ae.answers_given, 0) > 0
qualify
    row_number() over (
        partition by fu.user_id
        order by coalesce(rh.rn_hot, 999999), coalesce(aq.avg_question_score, -1) desc, fu.reputation desc
    ) = 1
order by
    coalesce(rh.rn_hot, 999999),
    fu.reputation desc,
    fu.user_id
limit 500;