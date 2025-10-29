-- {"query": "469.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3467} 
with recent_active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        u.lastaccessdate,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        (u.upvotes - u.downvotes) as net_votes,
        row_number() over (partition by coalesce(nullif(u.location, ''), 'Unknown') order by u.reputation desc, u.id) as loc_rank
    from users u
    where u.creationdate >= (select date_trunc('year', max(p.creationdate)) - interval '2 years' from posts p)
),
user_badge_stats as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as gold_cnt,
        count(*) filter (where b.class = 2) as silver_cnt,
        count(*) filter (where b.class = 3) as bronze_cnt,
        count(*) filter (where b.tagbased = 1) as tag_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_core as (
    select
        p.id as qid,
        p.owneruserid as q_owner_id,
        p.creationdate as q_created,
        p.title,
        p.tags,
        p.score as q_score,
        p.viewcount,
        p.answercount,
        p.closeddate,
        p.acceptedanswerid,
        p.favoritecount,
        p.commentcount,
        coalesce(p.tags like '%<sql>%', false) as has_sql_tag
    from posts p
    where p.posttypeid = 1
),
answer_core as (
    select
        a.id as aid,
        a.parentid as qid,
        a.owneruserid as a_owner_id,
        a.creationdate as a_created,
        a.score as a_score,
        a.commentcount as a_commentcount
    from posts a
    where a.posttypeid = 2
),
votes_agg as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(distinct case when v.votetypeid = 5 then v.userid end) as favorites,
        count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_amount_total
    from votes v
    group by v.postid
),
dup_links as (
    select pl.postid as dup_post_id, pl.relatedpostid as original_qid, count(*) as dup_link_count
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
history_flags as (
    select
        ph.postid,
        max(case when ph.posthistorytypeid = 10 then 1 else 0 end) as was_closed,
        max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as was_reopened,
        max(case when ph.posthistorytypeid in (12,10) then 1 else 0 end) as was_heavily_moderated,
        min(case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35) then ph.creationdate end) as first_mod_action
    from posthistory ph
    group by ph.postid
),
tag_exploded as (
    select
        q.qid,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
    from question_core q
    where q.tags is not null and length(q.tags) > 2
),
tag_rank as (
    select
        t.tagname,
        count(distinct te.qid) as q_count,
        row_number() over (order by count(distinct te.qid) desc, t.tagname) as tag_global_rank
    from tags t
    left join tag_exploded te on lower(te.tagname) = lower(t.tagname)
    group by t.tagname
),
answer_stats as (
    select
        ac.qid,
        count(*) as answers_total,
        count(*) filter (where ac.a_score > 0) as answers_positive,
        avg(ac.a_score::numeric) as avg_answer_score,
        max(ac.a_score) as max_answer_score,
        min(ac.a_score) as min_answer_score,
        percentile_disc(0.5) within group (order by ac.a_score) as median_answer_score
    from answer_core ac
    group by ac.qid
),
accepted_answer_enriched as (
    select
        q.qid,
        q.acceptedanswerid as accepted_aid,
        aa.a_score as accepted_score,
        aa.a_created as accepted_created,
        aa.a_owner_id as accepted_owner_id
    from question_core q
    left join answer_core aa on aa.aid = q.acceptedanswerid
),
question_activity as (
    select
        q.qid,
        q.q_owner_id,
        q.q_created,
        q.title,
        q.tags,
        q.q_score,
        q.viewcount,
        q.answercount,
        q.closeddate,
        q.favoritecount,
        q.commentcount,
        coalesce(v.upvotes, 0) as q_upvotes,
        coalesce(v.downvotes, 0) as q_downvotes,
        coalesce(v.favorites, 0) as q_favorites,
        coalesce(v.bounty_events, 0) as bounty_events,
        coalesce(v.bounty_amount_total, 0) as bounty_amount_total,
        coalesce(h.was_closed, 0) as was_closed,
        coalesce(h.was_reopened, 0) as was_reopened,
        h.first_mod_action,
        case when q.closeddate is not null then 1 else 0 end as is_closed_flag
    from question_core q
    left join votes_agg v on v.postid = q.qid
    left join history_flags h on h.postid = q.qid
),
user_enriched as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        u.lastaccessdate,
        u.websiteurl,
        u.net_votes,
        u.loc_rank,
        coalesce(ubs.gold_cnt, 0) as gold_cnt,
        coalesce(ubs.silver_cnt, 0) as silver_cnt,
        coalesce(ubs.bronze_cnt, 0) as bronze_cnt,
        coalesce(ubs.tag_badges, 0) as tag_badges,
        ubs.first_badge_date,
        ubs.last_badge_date
    from recent_active_users u
    left join user_badge_stats ubs on ubs.userid = u.user_id
),
question_user_join as (
    select
        qa.*,
        ue.displayname as owner_displayname,
        ue.reputation as owner_reputation,
        ue.location as owner_location,
        ue.net_votes as owner_net_votes,
        ue.loc_rank as owner_loc_rank,
        ue.gold_cnt,
        ue.silver_cnt,
        ue.bronze_cnt,
        ue.tag_badges,
        ue.first_badge_date,
        ue.last_badge_date
    from question_activity qa
    left join user_enriched ue on ue.user_id = qa.q_owner_id
),
answer_user_agg as (
    select
        ac.qid,
        count(distinct ac.a_owner_id) as distinct_answerers,
        max(ue.reputation) as max_answerer_rep,
        avg(ue.reputation::numeric) as avg_answerer_rep,
        sum(case when ue.gold_cnt > 0 then 1 else 0 end) as answers_by_gold_users
    from answer_core ac
    left join user_enriched ue on ue.user_id = ac.a_owner_id
    group by ac.qid
),
duplication_info as (
    select
        d.dup_post_id as qid,
        count(*) as dup_variants,
        min(d.original_qid) as smallest_original_qid,
        string_agg(distinct d.original_qid::text, ',') as original_qids
    from dup_links d
    group by d.dup_post_id
),
tag_mix as (
    select
        te.qid,
        count(*) as tag_count,
        sum(case when tr.tag_global_rank <= 100 then 1 else 0 end) as top100_tags,
        sum(case when lower(te.tagname) like any (array['%sql%','%join%','%postgres%','%mysql%']) then 1 else 0 end) as db_related_tags
    from tag_exploded te
    left join tag_rank tr on tr.tagname = te.tagname
    group by te.qid
),
accepted_owner as (
    select
        aee.qid,
        aee.accepted_aid,
        aee.accepted_score,
        aee.accepted_created,
        aee.accepted_owner_id,
        ue.displayname as accepted_owner_name,
        ue.reputation as accepted_owner_rep
    from accepted_answer_enriched aee
    left join user_enriched ue on ue.user_id = aee.accepted_owner_id
),
post_score_z as (
    select
        qc.qid,
        qc.q_score,
        (qc.q_score - avg(qc.q_score) over ()) / nullif(stddev_pop(qc.q_score) over (), 0) as q_score_z
    from question_core qc
),
question_windowed as (
    select
        qj.*,
        psz.q_score_z,
        row_number() over (order by coalesce(qj.q_upvotes - qj.q_downvotes, 0) desc, qj.viewcount desc, qj.qid) as global_activity_rank,
        rank() over (partition by coalesce(qj.owner_location, 'Unknown') order by qj.q_score desc nulls last, qj.viewcount desc nulls last) as loc_score_rank,
        sum(qj.q_upvotes) over (partition by coalesce(qj.owner_location, 'Unknown')) as loc_upvote_sum,
        sum(qj.viewcount) over (partition by coalesce(qj.owner_location, 'Unknown')) as loc_view_sum
    from question_user_join qj
    left join post_score_z psz on psz.qid = qj.qid
),
final_scored as (
    select
        qw.*,
        coalesce(asg.answers_total, 0) as answers_total,
        coalesce(asg.answers_positive, 0) as answers_positive,
        asg.avg_answer_score,
        asg.max_answer_score,
        asg.min_answer_score,
        asg.median_answer_score,
        coalesce(aua.distinct_answerers, 0) as distinct_answerers,
        coalesce(aua.max_answerer_rep, 0) as max_answerer_rep,
        coalesce(aua.avg_answerer_rep, 0) as avg_answerer_rep,
        coalesce(aua.answers_by_gold_users, 0) as answers_by_gold_users,
        coalesce(di.dup_variants, 0) as dup_variants,
        di.smallest_original_qid,
        di.original_qids,
        coalesce(tm.tag_count, 0) as tag_count,
        coalesce(tm.top100_tags, 0) as top100_tags,
        coalesce(tm.db_related_tags, 0) as db_related_tags,
        ao.accepted_aid,
        ao.accepted_score,
        ao.accepted_created,
        ao.accepted_owner_id,
        ao.accepted_owner_name,
        ao.accepted_owner_rep,
        case
            when qw.q_score_z > 2 then 'exceptional'
            when qw.q_score_z > 1 then 'great'
            when qw.q_score_z > 0 then 'good'
            when qw.q_score_z is null then 'unknown'
            else 'below_avg'
        end as score_band,
        case
            when qw.is_closed_flag = 1 and coalesce(di.dup_variants,0) > 0 then 'closed_duplicate'
            when qw.is_closed_flag = 1 then 'closed_other'
            else 'open'
        end as closure_category,
        case when qw.owner_reputation >= 10000 and coalesce(tm.db_related_tags,0) >= 1 then 1 else 0 end as is_high_rep_db_question,
        greatest(coalesce(qw.q_upvotes,0) - coalesce(qw.q_downvotes,0), 0) as net_upvotes,
        coalesce(qw.q_favorites,0) + coalesce(qw.favoritecount,0) as total_favorites,
        coalesce(qw.bounty_amount_total,0) as bounty_amount_total
    from question_windowed qw
    left join answer_stats asg on asg.qid = qw.qid
    left join answer_user_agg aua on aua.qid = qw.qid
    left join duplication_info di on di.qid = qw.qid
    left join tag_mix tm on tm.qid = qw.qid
    left join accepted_owner ao on ao.qid = qw.qid
),
topn as (
    select
        fs.*,
        row_number() over (
            order by
                (coalesce(fs.net_upvotes,0) * 2
                 + coalesce(fs.viewcount,0) / 100
                 + coalesce(fs.answers_positive,0) * 3
                 + coalesce(fs.bounty_amount_total,0) / 50
                 + case when fs.is_high_rep_db_question = 1 then 25 else 0 end
                 - coalesce(fs.dup_variants,0) * 5
                ) desc,
                fs.qid
        ) as composite_rank
    from final_scored fs
    where
        -- complex predicate mix
        (fs.tag_count >= 1 or fs.has_sql_tag = true)
        and (fs.viewcount is null or fs.viewcount >= 0)
        and not (fs.owner_location ilike '%test%' or fs.owner_displayname ilike '%bot%')
        and (fs.first_badge_date is null or fs.first_badge_date <= fs.q_created + interval '5 years')
)
select
    t.qid,
    t.q_created,
    t.title,
    t.tags,
    t.owner_displayname,
    t.owner_reputation,
    t.owner_location,
    t.q_score,
    t.q_score_z,
    t.net_upvotes,
    t.viewcount,
    t.answers_total,
    t.answers_positive,
    t.avg_answer_score,
    t.accepted_aid,
    t.accepted_score,
    t.accepted_owner_name,
    t.accepted_owner_rep,
    t.dup_variants,
    t.closure_category,
    t.score_band,
    t.tag_count,
    t.db_related_tags,
    t.global_activity_rank,
    t.loc_score_rank,
    t.total_favorites,
    t.bounty_amount_total,
    t.original_qids,
    t.composite_rank
from topn t
where
    (
        -- correlated existence check for at least one comment containing a URL or code block
        exists (
            select 1
            from comments c
            where c.postid = t.qid
              and (
                    c.text ~ 'https?://'
                    or c.text like '%`%`%'
                  )
        )
        or
        -- or has an answer with a highly upvoted comment by the same user as the accepted answer
        exists (
            select 1
            from comments c2
            join posts a on a.id = c2.postid and a.posttypeid = 2 and a.parentid = t.qid
            where c2.userid = t.accepted_owner_id
              and c2.score >= 5
        )
    )
  and (t.composite_rank <= 500 or (t.score_band in ('exceptional','great') and t.viewcount > 10000))
order by t.composite_rank, t.qid
limit 500;