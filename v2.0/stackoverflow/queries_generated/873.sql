-- {"query": "873.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3283} 
with recent_active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.lastaccessdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        max(b.date) as last_badge_date,
        row_number() over (order by u.reputation desc, u.id) as rn_rep
    from users u
    left join badges b on b.userid = u.id
    where u.lastaccessdate >= now() - interval '365 days'
    group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.location, u.websiteurl
),
question_activity as (
    select
        q.owneruserid as user_id,
        q.id as question_id,
        q.creationdate as question_created,
        q.score as question_score,
        q.viewcount as question_views,
        q.title,
        q.tags,
        q.acceptedanswerid,
        q.closeddate,
        count(a.id) as answers_count,
        max(a.creationdate) as last_answer_date,
        sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes_on_answers
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    left join votes v on v.postid = a.id and v.votetypeid in (2,3)
    where q.posttypeid = 1
      and q.creationdate >= now() - interval '365 days'
    group by q.owneruserid, q.id, q.creationdate, q.score, q.viewcount, q.title, q.tags, q.acceptedanswerid, q.closeddate
),
accepted_answerers as (
    select
        aa.id as answer_id,
        aa.owneruserid as answerer_id,
        aa.parentid as question_id,
        aa.creationdate as answer_created,
        aa.score as answer_score
    from posts aa
    where aa.posttypeid = 2
      and exists (
          select 1
          from posts q
          where q.id = aa.parentid
            and q.acceptedanswerid = aa.id
      )
),
tag_expansion as (
    select
        qa.user_id,
        qa.question_id,
        unnest(string_to_array(substring(qa.tags, 2, length(qa.tags)-2), '><')) as tag_name
    from question_activity qa
    where qa.tags is not null
),
user_tag_stats as (
    select
        te.user_id,
        t.id as tag_id,
        t.tagname,
        count(*) as tag_uses,
        sum(case when qa.acceptedanswerid is not null then 1 else 0 end) as tag_questions_with_accepted_answer
    from tag_expansion te
    join tags t on t.tagname = te.tag_name
    join question_activity qa on qa.question_id = te.question_id
    group by te.user_id, t.id, t.tagname
),
vote_agg as (
    select
        p.owneruserid as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_on_posts,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_on_posts,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_on_posts,
        count(*) filter (where v.votetypeid in (2,3)) as total_votes_on_posts
    from posts p
    left join votes v on v.postid = p.id
    where p.creationdate >= now() - interval '365 days'
    group by p.owneruserid
),
commenters as (
    select
        c.userid as user_id,
        count(*) as comments_made,
        sum(c.score) as comment_score_total,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.creationdate >= now() - interval '365 days'
    group by c.userid
),
post_hist_flags as (
    select
        ph.postid,
        max(case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20) then 1 else 0 end) as has_moderation_events,
        max(case when ph.posthistorytypeid = 10 then 1 else 0 end) as was_closed,
        max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as was_reopened,
        max(case when ph.posthistorytypeid = 50 then 1 else 0 end) as community_bumped
    from posthistory ph
    where ph.creationdate >= now() - interval '365 days'
    group by ph.postid
),
user_post_hist as (
    select
        p.owneruserid as user_id,
        sum(phf.has_moderation_events) as moderation_events_on_posts,
        sum(phf.was_closed) as posts_closed,
        sum(phf.was_reopened) as posts_reopened,
        sum(phf.community_bumped) as posts_bumped
    from posts p
    join post_hist_flags phf on phf.postid = p.id
    group by p.owneruserid
),
dup_links as (
    select
        pl.postid as question_id,
        pl.relatedpostid as original_id,
        pl.creationdate,
        pl.linktypeid
    from postlinks pl
    where pl.linktypeid = 3
),
dup_stats as (
    select
        q.owneruserid as user_id,
        count(*) as duplicates_marked,
        min(dl.creationdate) as first_duplicate_date,
        max(dl.creationdate) as last_duplicate_date
    from posts q
    join dup_links dl on dl.question_id = q.id
    group by q.owneruserid
),
user_quality as (
    select
        qa.user_id,
        count(*) as total_questions,
        avg(nullif(qa.question_score, 0)) as avg_nonzero_q_score,
        avg(qa.question_views) as avg_q_views,
        sum(case when qa.acceptedanswerid is not null then 1 else 0 end) as questions_with_accepted_answer,
        count(*) filter (where qa.closeddate is not null) as questions_closed,
        sum(qa.net_votes_on_answers) as net_votes_on_answers_to_their_questions,
        max(qa.last_answer_date) as last_answer_date_on_their_questions
    from question_activity qa
    group by qa.user_id
),
top_tag_per_user as (
    select
        uts.user_id,
        uts.tagname,
        uts.tag_uses,
        uts.tag_questions_with_accepted_answer,
        row_number() over (partition by uts.user_id order by uts.tag_uses desc, uts.tagname) as rn
    from user_tag_stats uts
),
answerer_interactions as (
    select
        aa.answerer_id as user_id,
        count(*) as accepted_answers_given,
        avg(aa.answer_score) as avg_accepted_answer_score,
        min(aa.answer_created) as first_accepted_answer_date,
        max(aa.answer_created) as last_accepted_answer_date
    from accepted_answerers aa
    group by aa.answerer_id
),
user_activity_span as (
    select
        u.id as user_id,
        min(p.creationdate) as first_post_date,
        max(p.creationdate) as last_post_date,
        extract(epoch from (max(p.creationdate) - min(p.creationdate))) / 86400.0 as active_days_span
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
score_percentiles as (
    select
        p.owneruserid as user_id,
        percentile_cont(0.5) within group (order by p.score) as p50_post_score,
        percentile_cont(0.9) within group (order by p.score) as p90_post_score
    from posts p
    where p.creationdate >= now() - interval '365 days'
    group by p.owneruserid
),
stringy as (
    select
        u.id as user_id,
        lower(coalesce(nullif(u.displayname, ''), 'unknown')) as dn_lower,
        substring(coalesce(u.location, ''), 1, 20) as location_prefix,
        length(coalesce(u.aboutme, '')) as about_len,
        position('http' in coalesce(u.websiteurl, '')) as has_http_in_website
    from users u
),
ranked_users as (
    select
        rau.*,
        coalesce(uq.total_questions, 0) as total_questions,
        coalesce(uq.avg_nonzero_q_score, 0) as avg_nonzero_q_score,
        coalesce(uq.avg_q_views, 0) as avg_q_views,
        coalesce(uq.questions_with_accepted_answer, 0) as q_with_accept,
        coalesce(uq.questions_closed, 0) as q_closed,
        coalesce(uq.net_votes_on_answers_to_their_questions, 0) as net_votes_on_answers,
        coalesce(va.upvotes_on_posts, 0) as upvotes_on_posts,
        coalesce(va.downvotes_on_posts, 0) as downvotes_on_posts,
        coalesce(va.favorites_on_posts, 0) as favorites_on_posts,
        coalesce(va.total_votes_on_posts, 0) as total_votes_on_posts,
        coalesce(c.comments_made, 0) as comments_made,
        coalesce(c.comment_score_total, 0) as comment_score_total,
        c.last_comment_date,
        coalesce(uph.moderation_events_on_posts, 0) as moderation_events_on_posts,
        coalesce(uph.posts_closed, 0) as posts_closed_by_hist,
        coalesce(uph.posts_reopened, 0) as posts_reopened_by_hist,
        coalesce(uph.posts_bumped, 0) as posts_bumped_by_hist,
        coalesce(ds.duplicates_marked, 0) as duplicates_marked,
        ds.first_duplicate_date,
        ds.last_duplicate_date,
        ttp.tagname as top_tag,
        ttp.tag_uses as top_tag_uses,
        ttp.tag_questions_with_accepted_answer as top_tag_accepts,
        coalesce(ai.accepted_answers_given, 0) as accepted_answers_given,
        coalesce(ai.avg_accepted_answer_score, 0) as avg_accepted_answer_score,
        ai.first_accepted_answer_date,
        ai.last_accepted_answer_date,
        uas.first_post_date,
        uas.last_post_date,
        uas.active_days_span,
        sp.p50_post_score,
        sp.p90_post_score,
        s.dn_lower,
        s.location_prefix,
        s.about_len,
        s.has_http_in_website,
        dense_rank() over (
            order by
                rau.reputation desc,
                coalesce(uq.avg_q_views, 0) desc,
                coalesce(va.total_votes_on_posts, 0) desc,
                coalesce(ai.accepted_answers_given, 0) desc,
                rau.user_id
        ) as rank_overall
    from recent_active_users rau
    left join user_quality uq on uq.user_id = rau.user_id
    left join vote_agg va on va.user_id = rau.user_id
    left join commenters c on c.user_id = rau.user_id
    left join user_post_hist uph on uph.user_id = rau.user_id
    left join dup_stats ds on ds.user_id = rau.user_id
    left join top_tag_per_user ttp on ttp.user_id = rau.user_id and ttp.rn = 1
    left join answerer_interactions ai on ai.user_id = rau.user_id
    left join user_activity_span uas on uas.user_id = rau.user_id
    left join score_percentiles sp on sp.user_id = rau.user_id
    left join stringy s on s.user_id = rau.user_id
),
outliers as (
    select
        ru.user_id,
        case
            when coalesce(ru.q_closed, 0) > greatest(5, coalesce(ru.total_questions, 0) * 0.5) then 'many_closed_questions'
            when coalesce(ru.downvotes_on_posts, 0) > coalesce(ru.upvotes_on_posts, 0) * 2 then 'more_downvotes_than_upvotes'
            when coalesce(ru.comment_score_total, 0) < 0 then 'negative_comment_karma'
            else null
        end as outlier_type
    from ranked_users ru
),
outlier_agg as (
    select
        user_id,
        array_agg(outlier_type) filter (where outlier_type is not null) as outlier_flags
    from outliers
    group by user_id
),
null_logic as (
    select
        ru.user_id,
        case
            when ru.top_tag is null and coalesce(ru.total_questions, 0) > 0 then 'no_tags_parsed'
            when ru.top_tag is null then 'no_activity'
            else 'ok'
        end as tag_parse_status,
        coalesce(ru.last_comment_date, ru.last_post_date, ru.creationdate) as last_seen_any_activity
    from ranked_users ru
)
select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.rank_overall,
    ru.gold_badges || '/' || ru.silver_badges || '/' || ru.bronze_badges as badge_mix,
    coalesce(ru.top_tag, 'none') as top_tag,
    ru.top_tag_uses,
    ru.total_questions,
    ru.q_with_accept,
    ru.q_closed,
    ru.upvotes_on_posts,
    ru.downvotes_on_posts,
    ru.favorites_on_posts,
    ru.total_votes_on_posts,
    ru.accepted_answers_given,
    ru.avg_accepted_answer_score,
    ru.avg_nonzero_q_score,
    ru.avg_q_views,
    ru.p50_post_score,
    ru.p90_post_score,
    ru.moderation_events_on_posts,
    ru.posts_closed_by_hist,
    ru.posts_reopened_by_hist,
    ru.posts_bumped_by_hist,
    ru.duplicates_marked,
    ru.active_days_span,
    nl.tag_parse_status,
    nl.last_seen_any_activity,
    oa.outlier_flags,
    case
        when ru.websiteurl_norm ilike '%stack%' then 'stack-affinity'
        when ru.websiteurl_norm = 'n/a' then 'no-site'
        else 'external-site'
    end as site_bucket
from ranked_users ru
left join outlier_agg oa on oa.user_id = ru.user_id
left join null_logic nl on nl.user_id = ru.user_id
where (ru.gold_badges + ru.silver_badges + ru.bronze_badges) >= 0
  and (ru.upvotes_on_posts - ru.downvotes_on_posts) is not null
  and (ru.accepted_answers_given is null or ru.accepted_answers_given >= 0)
order by ru.rank_overall, ru.user_id
limit 250;