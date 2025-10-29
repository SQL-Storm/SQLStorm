-- {"query": "2898.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1722} 
with ranked_posts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Title,
        p.Tags,
        u.DisplayName as OwnerDisplayName,
        dense_rank() over (
            partition by p.PostTypeId
            order by p.Score desc, p.ViewCount desc nulls last, p.CreationDate asc
        ) as rank_score_view
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2) -- questions and answers
), badge_counts as (
    select
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as gold_badges,
        sum(case when Class = 2 then 1 else 0 end) as silver_badges,
        sum(case when Class = 3 then 1 else 0 end) as bronze_badges
    from Badges
    group by UserId
), question_answer_links as (
    select
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.OwnerUserId as AnswerOwner,
        u.DisplayName as AnswerOwnerName
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1
), latest_comments as (
    select distinct on (c.PostId)
        c.PostId,
        c.Id as CommentId,
        c.Score as CommentScore,
        c.CreationDate as CommentCreationDate,
        coalesce(u.DisplayName, c.UserDisplayName) as CommentUser
    from Comments c
    left join Users u on c.UserId = u.Id
    order by c.PostId, c.CreationDate desc
), close_reason_counts as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    inner join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.Comment, crt.Name
), question_with_scores as (
    select
        rp.*,
        bc.gold_badges,
        bc.silver_badges,
        bc.bronze_badges,
        (rp.Score * 2 + coalesce(bc.gold_badges, 0) * 10 + coalesce(bc.silver_badges, 0) * 5 + coalesce(bc.bronze_badges, 0)) as composite_score,
        case
            when rp.ViewCount > 10000 then 'Very High'
            when rp.ViewCount between 5000 and 10000 then 'High'
            when rp.ViewCount between 1000 and 4999 then 'Medium'
            else 'Low'
        end as ViewCategory,
        (select count(*) from Comments c where c.PostId = rp.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = rp.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = rp.Id and v.VoteTypeId = 3) as DownVotes
    from ranked_posts rp
    left join badge_counts bc on rp.OwnerUserId = bc.UserId
    where rp.PostTypeId = 1
), duplicated_questions as (
    select distinct
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    where pl.LinkTypeId = 3 -- Duplicate
), question_stats as (
    select
        qws.Id,
        qws.Title,
        qws.OwnerDisplayName,
        qws.CreationDate,
        qws.Score,
        qws.ViewCount,
        qws.composite_score,
        qws.ViewCategory,
        qws.CommentCount,
        qws.UpVotes,
        qws.DownVotes,
        coalesce(dq.OriginalQuestionId, null) as DuplicateOf,
        array_to_string(
            array(
                select regexp_split_to_array(
                    replace(
                        coalesce(qws.Tags, ''),
                        '><', ','),
                    ',')
            ), ',') as TagList
    from question_with_scores qws
    left join duplicated_questions dq on qws.Id = dq.DuplicateQuestionId
), final_ranking as (
    select
        qs.Id,
        qs.Title,
        qs.OwnerDisplayName,
        qs.CreationDate,
        qs.Score,
        qs.ViewCount,
        qs.composite_score,
        qs.ViewCategory,
        qs.CommentCount,
        qs.UpVotes,
        qs.DownVotes,
        qs.DuplicateOf,
        qs.TagList,
        rank() over (order by qs.composite_score desc, qs.ViewCount desc nulls last) as FinalRank
    from question_stats qs
), tagged_badged_users as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) as BadgeCount,
        string_agg(distinct t.TagName, ', ') as Tags
    from Users u
    left join Badges b on b.UserId = u.Id and b.TagBased = 1
    left join Tags t on t.TagName = b.Name
    group by u.Id, u.DisplayName
    having count(b.Id) > 0
)
select
    fr.FinalRank,
    fr.Id as QuestionId,
    fr.Title,
    fr.OwnerDisplayName,
    fr.CreationDate,
    fr.Score,
    fr.ViewCount,
    fr.composite_score,
    fr.ViewCategory,
    fr.CommentCount,
    fr.UpVotes,
    fr.DownVotes,
    fr.DuplicateOf,
    fr.TagList,
    (select json_agg(json_build_object('AnswerId', qa.AnswerId, 'AnswerScore', qa.AnswerScore, 'AnswerOwner', qa.AnswerOwnerName, 'AnswerCreationDate', qa.AnswerCreationDate))
     from question_answer_links qa where qa.QuestionId = fr.Id) as Answers,
    (select json_agg(json_build_object('CommentId', lc.CommentId, 'CommentScore', lc.CommentScore, 'CommentCreationDate', lc.CommentCreationDate, 'CommentUser', lc.CommentUser))
     from latest_comments lc where lc.PostId = fr.Id) as LatestComments,
    (select json_build_object('Gold', coalesce(bc.gold_badges, 0), 'Silver', coalesce(bc.silver_badges, 0), 'Bronze', coalesce(bc.bronze_badges, 0))
     from badge_counts bc where bc.UserId = (select OwnerUserId from Posts p2 where p2.Id = fr.Id)) as OwnerBadgeSummary,
    (select count(*) from Votes v where v.PostId = fr.Id and v.VoteTypeId = 5) as FavoriteCount, -- bonus votes count
    (select sum(case when v.VoteTypeId in (2,5) then 1 when v.VoteTypeId = 3 then -1 else 0 end) from Votes v where v.PostId = fr.Id) as NetVotes,
    (select count(*) from PostHistory ph where ph.PostId = fr.Id and ph.PostHistoryTypeId in (10, 11)) as CloseReopenEventCount,
    (select count(distinct u.Id) from Users u
     where u.Id in (
            select p.OwnerUserId from Posts p where p.Tags like '%' || split_part(fr.TagList, ',', 1) || '%'
        ) and u.Reputation > 10000) as HighRepUsersWithTag,
    (select string_agg(distinct b.Name, ', ')
     from Badges b
     where b.UserId = fr.Id and b.Class = 1) as GoldBadgesForQuestionOwner
from final_ranking fr
order by fr.FinalRank
limit 50;