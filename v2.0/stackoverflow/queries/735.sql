-- {"query": "735.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3089}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
active_questions as (
    select
        p.id as question_id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.title,
        p.tags,
        p.closeddate,
        p.lastactivitydate,
        case when p.closeddate is not null then 1 else 0 end as is_closed,
        case when p.acceptedanswerid is not null then 1 else 0 end as has_accepted
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from posts where posttypeid = 1)
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid,
        a.creationdate,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
question_votes as (
    select
        v.postid as question_id,
        sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        count(*) filter (where v.votetypeid in (2,3)) as total_votes
    from votes v
    join active_questions q on q.question_id = v.postid
    group by v.postid
),
comment_activity as (
    select
        c.postid as post_id,
        count(*) as comments_count,
        max(c.creationdate) as last_comment_date,
        sum(case when coalesce(length(c.text),0) > 280 then 1 else 0 end) as long_comments
    from comments c
    where c.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from comments)
    group by c.postid
),
tag_expansion as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
    from active_questions q
    where q.tags is not null and length(q.tags) > 2
),
tag_stats as (
    select
        te.question_id,
        count(*) as tag_count,
        sum(case when lower(te.tagname) like '%sql%' or lower(te.tagname) like '%postgres%' or lower(te.tagname) like '%mysql%' or lower(te.tagname) like '%server%' then 1 else 0 end) as is_db_related
    from tag_expansion te
    group by te.question_id
),
dup_links as (
    select
        pl.postid as question_id,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as linked_links
    from postlinks pl
    join active_questions q on q.question_id = pl.postid
    group by pl.postid
),
edits as (
    select
        ph.postid as question_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
        count(*) filter (where ph.posthistorytypeid = 24) as suggested_edits_applied,
        count(*) filter (where ph.posthistorytypeid in (10,11)) as open_close_events,
        max(ph.creationdate) as last_edit_date,
        max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_close_date
    from posthistory ph
    join active_questions q on q.question_id = ph.postid
    group by ph.postid
),
user_badges as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(*) filter (where b.tagbased) as tag_badges
    from badges b
    group by b.userid
),
answerers as (
    select
        a.question_id,
        count(distinct a.owneruserid) as distinct_answerers,
        avg(a.answer_score) as avg_answer_score,
        max(a.answer_score) as max_answer_score,
        min(a.creationdate) as first_answer_date
    from answers a
    group by a.question_id
),
question_quality as (
    select
        q.question_id,
        coalesce(qv.net_votes,0) as net_votes,
        coalesce(q.viewcount,0) as views,
        coalesce(q.answercount,0) as answers_count,
        coalesce(qa.distinct_answerers,0) as distinct_answerers,
        coalesce(qa.avg_answer_score,0) as avg_answer_score,
        coalesce(qa.max_answer_score,0) as max_answer_score,
        coalesce(ts.tag_count,0) as tag_count,
        coalesce(ts.is_db_related,0) as is_db_related,
        coalesce(dl.duplicate_links,0) as duplicate_links,
        coalesce(dl.linked_links,0) as linked_links,
        coalesce(e.edit_count,0) as edit_count,
        coalesce(e.suggested_edits_applied,0) as suggested_edits_applied,
        coalesce(e.open_close_events,0) as open_close_events,
        coalesce(ca.comments_count,0) as comments_count,
        coalesce(ca.long_comments,0) as long_comments,
        q.has_accepted,
        q.is_closed
    from active_questions q
    left join question_votes qv on qv.question_id = q.question_id
    left join answerers qa on qa.question_id = q.question_id
    left join tag_stats ts on ts.question_id = q.question_id
    left join dup_links dl on dl.question_id = q.question_id
    left join edits e on e.question_id = q.question_id
    left join comment_activity ca on ca.post_id = q.question_id
),
user_rollup as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        coalesce(ub.tag_badges,0) as tag_badges,
        u.creationdate,
        u.location,
        u.websiteurl
    from users u
    left join user_badges ub on ub.userid = u.id
),
question_owner as (
    select
        q.question_id,
        u.user_id,
        u.displayname,
        u.reputation,
        u.gold_badges,
        u.silver_badges,
        u.bronze_badges,
        u.tag_badges
    from active_questions q
    left join user_rollup u on u.user_id = q.owneruserid
),
ranked_questions as (
    select
        qq.*,
        row_number() over (
            order by
                (coalesce(net_votes,0) * 2
                 + coalesce(views,0) / 100
                 + coalesce(answers_count,0) * 3
                 + coalesce(has_accepted,0) * 10
                 - coalesce(is_closed,0) * 5
                 - coalesce(duplicate_links,0) * 2
                 + coalesce(edit_count,0)
                 + coalesce(suggested_edits_applied,0) * 2
                 + coalesce(comments_count,0) / 5
                 + coalesce(is_db_related,0) * 4
                ) desc,
                coalesce(max_answer_score, -9999) desc
        ) as rank_score
    from question_quality qq
),
db_tags as (
    select t.tagname
    from tags t
    where lower(t.tagname) similar to '(sql|postgres%|mysql|server%|database|sqlite|tsql|pl/sql)%'
),
questions_with_tag_presence as (
    select
        q.question_id,
        max(case when lower(te.tagname) = lower(dt.tagname) then 1 else 0 end) as has_db_tag
    from active_questions q
    left join tag_expansion te on q.question_id = te.question_id
    cross join db_tags dt
    group by q.question_id
),
owner_activity as (
    select
        q.question_id,
        sum(case when c.userid = q.owneruserid then 1 else 0 end) as owner_comments,
        max(case when c.userid = q.owneruserid then c.creationdate end) as last_owner_comment
    from active_questions q
    left join comments c on q.question_id = c.postid
    group by q.question_id
),
cte_union as (
    select question_id from active_questions
    union
    select postid as question_id from comments
),
cte_intersect as (
    select question_id
    from active_questions
    intersect
    select postid as question_id from comments
),
final as (
    select
        rq.rank_score,
        aq.question_id,
        left(coalesce(p.title, ''), 120) as title_prefix,
        coalesce(p.viewcount,0) as views,
        coalesce(p.score,0) as score,
        qq.answers_count,
        qq.distinct_answerers,
        qq.has_accepted,
        qq.is_closed,
        qq.tag_count,
        qq.is_db_related,
        qtp.has_db_tag,
        qq.net_votes,
        qq.max_answer_score,
        qq.edit_count,
        qq.suggested_edits_applied,
        qq.open_close_events,
        qq.duplicate_links,
        qq.linked_links,
        qq.comments_count,
        oa.owner_comments,
        qown.user_id as owner_id,
        coalesce(qown.displayname, '[unknown]') as owner_name,
        coalesce(qown.reputation, 0) as owner_rep,
        coalesce(qown.gold_badges,0) as owner_gold,
        coalesce(qown.silver_badges,0) as owner_silver,
        coalesce(qown.bronze_badges,0) as owner_bronze,
        case
            when aq.closeddate is not null then 'Closed'
            when qq.has_accepted = 1 then 'Answered'
            when qq.answers_count > 0 then 'Has Answers'
            else 'Open'
        end as question_state,
        case
            when p.tags is null then 0
            when position('sql' in lower(p.tags)) > 0 then 1
            else 0
        end as tag_contains_sql_substr,
        (select count(*) from answers a2 where a2.question_id = aq.question_id and coalesce(a2.answer_score,0) > 0) as positive_answers,
        (select count(*) from answers a3 where a3.question_id = aq.question_id and coalesce(a3.answer_score,0) <= 0) as non_positive_answers,
        (select avg(a4.answer_score) from answers a4 where a4.question_id = aq.question_id) as avg_ans_score_subq,
        (select sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end)
         from votes v
         where v.postid = aq.question_id
           and v.creationdate >= aq.creationdate) as net_votes_since_post,
        (select count(*) from cte_union cu where cu.question_id = aq.question_id) as union_presence,
        (select count(*) from cte_intersect ci where ci.question_id = aq.question_id) as intersect_presence,
        coalesce(ph_last.creationdate, p.lastactivitydate) as last_major_event,
        nullif(trim(p.ownerdisplayname), '') as owner_display_name_fallback
    from ranked_questions rq
    join active_questions aq on aq.question_id = rq.question_id
    left join posts p on p.id = aq.question_id
    left join question_quality qq on qq.question_id = aq.question_id
    left join question_owner qown on qown.question_id = aq.question_id
    left join questions_with_tag_presence qtp on qtp.question_id = aq.question_id
    left join owner_activity oa on oa.question_id = aq.question_id
    left join lateral (
        select ph.creationdate
        from posthistory ph
        where ph.postid = aq.question_id
          and ph.posthistorytypeid in (4,5,6,10,11,12,13,19,20,24,35,36,37,38,50,52,53)
        order by ph.creationdate desc
        limit 1
    ) ph_last on true
)
select *
from final
where
    (
        (coalesce(views,0) > 1000 and coalesce(score,0) >= 0)
        or (coalesce(is_db_related,0) > 0 and coalesce(tag_contains_sql_substr,0) = 1)
        or (coalesce(has_accepted,0) = 1 and coalesce(max_answer_score, -1) >= 1)
    )
    and coalesce(edit_count,0) + coalesce(suggested_edits_applied,0) >= 0
    and (owner_name is not null or owner_display_name_fallback is not null)
    and coalesce(duplicate_links,0) <= coalesce(linked_links,0) + 5
    and (coalesce(comments_count,0) > 0 or coalesce(net_votes,0) <> 0)
order by rank_score asc nulls last, last_major_event desc
limit 250;