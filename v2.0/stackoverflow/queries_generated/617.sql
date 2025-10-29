-- {"query": "617.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3111} 
with recent_active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        u.lastaccessdate,
        u.upvotes,
        u.downvotes,
        coalesce(u.views, 0) as profile_views,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        max(b.date) as last_badge_date
    from users u
    left join badges b
      on b.userid = u.id
    where u.lastaccessdate >= now() - interval '365 days'
    group by u.id, u.displayname, u.reputation, u.location, u.creationdate, u.lastaccessdate, u.upvotes, u.downvotes, u.views
), user_post_stats as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        sum(p.score) filter (where p.posttypeid in (1,2)) as total_score,
        avg(nullif(p.score,0)) filter (where p.posttypeid = 1) as avg_q_score_nonzero,
        avg(nullif(p.score,0)) filter (where p.posttypeid = 2) as avg_a_score_nonzero,
        max(p.viewcount) filter (where p.posttypeid = 1) as max_q_views,
        count(*) filter (where p.closeddate is not null and p.posttypeid = 1) as closed_questions,
        count(*) filter (where p.acceptedanswerid is not null) as questions_with_accepted
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
), post_activity as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.closeddate,
        p.title,
        p.tags,
        sum(vote_weight) over (partition by p.id) as weighted_votes,
        sum(case when vt.name = 'UpMod' then 1 when vt.name = 'DownMod' then -1 else 0 end) over (partition by p.id) as net_votes
    from posts p
    left join (
        select v.postid, v.votetypeid,
               case
                   when v.votetypeid = 2 then 1
                   when v.votetypeid = 3 then -1
                   when v.votetypeid = 1 then 2
                   when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) / 50
                   else 0
               end as vote_weight
        from votes v
    ) w on w.postid = p.id
    left join votetypes vt on vt.id = w.votetypeid
), tag_splits as (
    select
        p.id as post_id,
        lower(trim(t)) as tag
    from posts p
    cross join lateral unnest(
        case
            when p.tags is null then array[]::varchar[]
            else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
        end
    ) as t
    where p.posttypeid = 1
), user_top_tags as (
    select
        p.owneruserid as user_id,
        ts.tag,
        count(*) as tag_q_count,
        sum(p.score) as tag_q_score,
        row_number() over (partition by p.owneruserid order by count(*) desc, sum(p.score) desc, min(p.creationdate)) as rn
    from posts p
    join tag_splits ts on ts.post_id = p.id
    where p.posttypeid = 1
    group by p.owneruserid, ts.tag
), duplicates_and_links as (
    select
        pl.postid as post_id,
        pl.relatedpostid as related_id,
        lt.name as link_type,
        count(*) over (partition by pl.postid, pl.linktypeid) as link_type_count
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid
), post_history_flags as (
    select
        ph.postid,
        max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as ever_closed,
        max(case when ph.posthistorytypeid in (11) then 1 else 0 end) as ever_reopened,
        max(case when ph.posthistorytypeid in (12) then 1 else 0 end) as ever_deleted,
        max(case when ph.posthistorytypeid in (13) then 1 else 0 end) as ever_undeleted,
        max(case when ph.posthistorytypeid in (19) then 1 else 0 end) as ever_protected
    from posthistory ph
    group by ph.postid
), question_answer_latency as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        a.id as answer_id,
        a.owneruserid as answerer_id,
        a.creationdate - q.creationdate as answer_latency,
        row_number() over (partition by q.id order by a.creationdate) as rn_first_answer,
        row_number() over (partition by q.id order by a.score desc nulls last, a.creationdate) as rn_top_answer
    from posts q
    left join posts a
      on a.parentid = q.id
     and a.posttypeid = 2
    where q.posttypeid = 1
), user_activity_windows as (
    select
        pa.user_id,
        count(*) filter (where pa.posttypeid = 1) as posts_total,
        count(*) filter (where pa.posttypeid = 1 and pa.creationdate >= now() - interval '30 days') as posts_30d,
        count(*) filter (where pa.posttypeid = 2 and pa.creationdate >= now() - interval '30 days') as answers_30d,
        percentile_cont(0.5) within group (order by coalesce(pa.viewcount,0)) as median_views_per_post,
        avg(pa.net_votes) as avg_net_votes_per_post
    from post_activity pa
    group by pa.user_id
), heavy_predicate_posts as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        case
            when coalesce(p.viewcount,0) > greatest(1000, 10 * coalesce(p.score,0))
             and p.score >= 5
             and (p.favoritecount is not null and p.favoritecount >= coalesce(p.commentcount,0))
             and (p.closeddate is null or p.closeddate > now() - interval '365 days')
            then 1 else 0
        end as is_engaging_recent,
        case
            when exists (
                select 1
                from comments c
                where c.postid = p.id
                  and c.score >= 5
                  and c.creationdate >= p.creationdate
                  and c.creationdate <= p.creationdate + interval '7 days'
            ) then 1 else 0
        end as has_early_hot_comment
    from posts p
), user_rank as (
    select
        rau.user_id,
        rau.displayname,
        rau.reputation,
        rau.location,
        ups.questions,
        ups.answers,
        ups.total_score,
        coalesce(ups.max_q_views,0) as max_q_views,
        coalesce(ups.closed_questions,0) as closed_questions,
        coalesce(ups.questions_with_accepted,0) as questions_with_accepted,
        rau.gold_badges,
        rau.silver_badges,
        rau.bronze_badges,
        uaw.posts_30d,
        uaw.answers_30d,
        uaw.median_views_per_post,
        uaw.avg_net_votes_per_post,
        coalesce(nullif(rau.displayname,''), concat('user#', rau.user_id::text)) as stable_displayname,
        sum(case when hpp.is_engaging_recent = 1 then 1 else 0 end) as engaging_recent_posts,
        sum(case when hpp.has_early_hot_comment = 1 then 1 else 0 end) as early_hot_comment_posts
    from recent_active_users rau
    left join user_post_stats ups on ups.user_id = rau.user_id
    left join user_activity_windows uaw on uaw.user_id = rau.user_id
    left join heavy_predicate_posts hpp on hpp.user_id = rau.user_id
    group by
        rau.user_id, rau.displayname, rau.reputation, rau.location,
        ups.questions, ups.answers, ups.total_score, ups.max_q_views,
        ups.closed_questions, ups.questions_with_accepted,
        rau.gold_badges, rau.silver_badges, rau.bronze_badges,
        uaw.posts_30d, uaw.answers_30d, uaw.median_views_per_post, uaw.avg_net_votes_per_post
), ranked_users as (
    select
        ur.*,
        coalesce((ur.reputation::numeric
                 + 10 * coalesce(ur.questions,0)
                 + 15 * coalesce(ur.answers,0)
                 + 2 * coalesce(ur.total_score,0)
                 + 50 * coalesce(ur.gold_badges,0)
                 + 20 * coalesce(ur.silver_badges,0)
                 + 10 * coalesce(ur.bronze_badges,0)
                 + 5 * coalesce(ur.posts_30d,0)
                 + 7 * coalesce(ur.answers_30d,0)
                 + 3 * coalesce(ur.engaging_recent_posts,0)
                 + 2 * coalesce(ur.early_hot_comment_posts,0)
                 + greatest(0, ur.avg_net_votes_per_post)*10
        ),0)::numeric as activity_score
    from user_rank ur
), top_questions_per_user as (
    select
        p.owneruserid as user_id,
        p.id as question_id,
        p.title,
        p.score,
        p.viewcount,
        dense_rank() over (partition by p.owneruserid order by coalesce(p.score, -999999) desc, coalesce(p.viewcount,0) desc, p.creationdate desc) as dr
    from posts p
    where p.posttypeid = 1
), accepted_answer_ratio as (
    select
        q.owneruserid as user_id,
        count(*) filter (where q.acceptedanswerid is not null) :: numeric
          / nullif(count(*) filter (where q.posttypeid = 1),0) as accept_rate
    from posts q
    where q.posttypeid = 1
    group by q.owneruserid
), first_and_top_answer_lags as (
    select
        qal.asker_id as user_id,
        avg(extract(epoch from qal.answer_latency)) filter (where qal.rn_first_answer = 1) as avg_seconds_to_first_answer,
        avg(extract(epoch from qal.answer_latency)) filter (where qal.rn_top_answer = 1) as avg_seconds_to_top_answer
    from question_answer_latency qal
    where qal.answer_latency is not null
    group by qal.asker_id
), dupe_network as (
    select
        d.post_id,
        count(*) filter (where d.link_type = 'Duplicate') as dup_edges,
        count(*) filter (where d.link_type <> 'Duplicate') as other_edges
    from duplicates_and_links d
    group by d.post_id
), user_tag_focus as (
    select
        utt.user_id,
        string_agg(utt.tag, ', ' order by utt.rn) as top_3_tags,
        sum(utt.tag_q_count) as tag_total_qs
    from user_top_tags utt
    where utt.rn <= 3
    group by utt.user_id
), filtered_ranked as (
    select
        ru.*,
        rank() over (order by ru.activity_score desc nulls last, ru.reputation desc, ru.user_id) as rnk_global,
        ntile(10) over (order by ru.activity_score desc nulls last) as decile
    from ranked_users ru
    where coalesce(ru.answers,0) + coalesce(ru.questions,0) >= 5
)
select
    fr.rnk_global,
    fr.decile,
    fr.user_id,
    fr.stable_displayname as displayname,
    fr.location,
    fr.reputation,
    fr.questions,
    fr.answers,
    fr.total_score,
    fr.gold_badges,
    fr.silver_badges,
    fr.bronze_badges,
    fr.posts_30d,
    fr.answers_30d,
    round(fr.activity_score,2) as activity_score,
    round(coalesce(ar.accept_rate,0)::numeric,3) as accept_rate,
    round(coalesce(fatl.avg_seconds_to_first_answer,0)::numeric,1) as avg_sec_to_first_answer,
    round(coalesce(fatl.avg_seconds_to_top_answer,0)::numeric,1) as avg_sec_to_top_answer,
    coalesce(utf.top_3_tags, '(none)') as top_tags,
    coalesce(utf.tag_total_qs,0) as top_tags_qs,
    tq.title as best_question_title,
    coalesce(tq.score,0) as best_question_score,
    coalesce(tq.viewcount,0) as best_question_views,
    coalesce(dn.dup_edges,0) as dup_links_on_best_q,
    coalesce(dn.other_edges,0) as other_links_on_best_q
from filtered_ranked fr
left join accepted_answer_ratio ar on ar.user_id = fr.user_id
left join first_and_top_answer_lags fatl on fatl.user_id = fr.user_id
left join user_tag_focus utf on utf.user_id = fr.user_id
left join top_questions_per_user tq
  on tq.user_id = fr.user_id
 and tq.dr = 1
left join dupe_network dn
  on dn.post_id = tq.question_id
where fr.decile in (1,2,3,4,5,6,7,8,9,10)
order by fr.rnk_global
limit 200;