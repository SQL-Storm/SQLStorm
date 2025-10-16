-- {"query": "1406.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2074} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswersProvided,
        coalesce(sum(vp_upc.UpVotesCount),0) as TotalUpVotesReceived,
        coalesce(sum(vp_downc.DownVotesCount),0) as TotalDownVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join lateral (
        select p3.OwnerUserId, count(v.Id) as UpVotesCount
        from Posts p3
        join Votes v on v.PostId = p3.Id and v.VoteTypeId = 2 
        where p3.OwnerUserId = u.Id
        group by p3.OwnerUserId
    ) vp_upc on vp_upc.OwnerUserId = u.Id
    left join lateral (
        select p4.OwnerUserId, count(v.Id) as DownVotesCount
        from Posts p4
        join Votes v on v.PostId = p4.Id and v.VoteTypeId = 3
        where p4.OwnerUserId = u.Id
        group by p4.OwnerUserId
    ) vp_downc on vp_downc.OwnerUserId = u.Id
    group by u.Id
), RankedPosts as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        row_number() over (
            partition by p.PostTypeId
            order by p.ViewCount desc nulls last, p.Score desc nulls last, p.CreationDate desc nulls last
        ) as RankByPopularity,
        dense_rank() over (partition by p.PostTypeId order by date_trunc('month', p.CreationDate)) as MonthRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
),
QualifiedDuplicates as (
    select 
        pl.PostId, pl.RelatedPostId, pl.CreationDate, lt.Name as LinkTypeName,
        p_main.Title as MainTitle,
        p_rel.Title as RelatedTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p_main on p_main.Id = pl.PostId
    join Posts p_rel on p_rel.Id = pl.RelatedPostId
    where pl.CreationDate >= current_date - interval '3 years'
), 
BestUserBadgeBadges as (
    select 
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        bool_or(b.TagBased) as HasAnyTagBased
    from Badges b
    group by b.UserId
),
ComplexCommentScoresFinally as (
    select
        c.Id,
        c.PostId,
        c.UserDisplayName,
        c.UserId,
        c.CreationDate,
        c.Score,
        -- Calculate normalized score difference making NULLs 0 and combine with text length
        coalesce(c.Score, 0) - 
        (select avg(coalesce(c2.Score,0)) 
         from Comments c2 
         where c2.PostId = c.PostId) as NormalizedScoreDiff,
        length(c.Text) as CommentLength,
        row_number() over (partition by c.PostId order by c.Score desc nulls last) as CommentScoreRank
    from Comments c
),
AnswersAggregateForQuestions as (
    select
        q.Id as QuestionId,
        count(a.Id) as NumUndeletedAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        coalesce(sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end), 0) as HasAcceptedAnswer
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
),
ActiveUsersWithComplexCriteria as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        bur.GoldBadges, bur.SilverBadges, bur.BronzeBadges,
        r.score_rank
    from Users u
    left join BestUserBadgeBadges bur on bur.UserId = u.Id
    join (
        select UserId,
            rank() over (
                order by Reputation desc, CoalesceGold.badge_count desc, SilverBadges desc nulls last
            ) as score_rank
        from Users
        left join (
            select UserId, count(*) as badge_count
            from Badges
            where Class = 1
            group by UserId
        ) CoalesceGold on CoalesceGold.UserId = Users.Id
        left join BestUserBadgeBadges consequent on consequent.UserId = Users.Id
    ) r on r.UserId = u.Id
    where u.Reputation > 1000 and (bur.GoldBadges > 0 or bur.SilverBadges > 2)
),
EnhancedQuestionsWithHitsAndLinks AS (
    select 
        q.*,
        qa.NumUndeletedAnswers,
        qa.MaxAnswerScore,
        qa.AvgAnswerScore,
        q.AcceptedAnswerId,
        newest_comment.Created sp_top_comment_creation,
        repo_SelectedHotQuestion.CreationDate as HotNetworkDate,
        linkedDup.RelatedPostId as DuplicateOfPost,
        linkedDup.LinkTypeName as Relation
    from Posts q
    left join AnswersAggregateForQuestions qa on qa.QuestionId = q.Id
    left join LATERAL (
        select cc.CreationDate
        from Comments cc
        where cc.PostId = q.Id
        order by cc.Score desc nulls last, cc.CreationDate desc
        limit 1
    ) newest_comment on true
    left join PostLinks linkedDup on linkedDup.PostId = q.Id and
         linkedDup.Relation = 'Duplicate'
    left join PostHistory repo_SelectedHotQuestion on 
        repo_SelectedHotQuestion.PostId = q.Id and 
        repo_SelectedHotQuestion.PostHistoryTypeId = 52
    where q.PostTypeId = 1 and q.ViewCount is not null and q.AnswerCount > 3
),
RecursiveTagPaths(tag_id, tag_name, occurrence_path, depth) AS (
    select 
        t.Id,
        t.TagName,
        ARRAY[t.TagName]::varchar[],
        1
    from Tags t
    where not t.IsModeratorOnly = 1 and t.Count > 100
    union all
    select 
        t2.Id, 
        t2.TagName,
        r.occurrence_path || t2.TagName,
        r.depth + 1
    from Tags t2
    join RecursiveTagPaths r on array_position(r.occurrence_path, t2.TagName) is null and r.depth < 3
    where t2.Count > 50
)
select distinct
    eswch.PostId,
    eswch.Title,
    eswch.Tags,
    eswch.CreationDate,
    uac.DisplayName as OwnerName,
    uac.Reputation,
    uac.GoldBadges,
    uac.SilverBadges,
    uac.BronzeBadges,
    eswch.ViewCount,
    eswch.Score,
    eswch.NumUndeletedAnswers,
    eswch.MaxAnswerScore,
    coalesce(b.ScoreRank,0) as PopularityRank,
    case when eswch.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
    coalesce(hot_post_recent_days, -1) as DaysSinceHotNetwork,
    -- Fully unpack tags and count final over window everywhere renouce (+ complex like with lateral concat_parts)
    (select array_to_string(array_agg(ts.TagName order by ts.Count desc), ', ')
     from Tags ts
     where ts.Id in (
         select distinct rtp.tag_id
         from RecursiveTagPaths rtp
         where rtp.tag_name = any(string_to_array(substring(eswch.Tags from 2 for char_length(eswch.Tags)-2), '><'))
     )) AS RelatedTagsChain,
    coalesce(qa_Havings.NumUndeletedAnswers, 0) as CommentedAnswersCount
from EnhancedQuestionsWithHitsAndLinks eswch
join Users uac on uac.Id = eswch.OwnerUserId
left join RankedPosts b on b.PostId = eswch.PostId 
left join ActiveUsersWithComplexCriteria auc on auc.UserId = uac.Id
left join LATERAL (
    select abs(date_part('day', now() - ph.CreatedAt)) as hot_post_recent_days 
    from PostHistory ph
    where ph.PostId = eswch.PostId and ph.PostHistoryTypeId = 52
    order by ph.CreatedAt desc
    limit 1
) hh on true
left join AnswersAggregateForQuestions qa_Havings on qa_Havings.QuestionId = eswch.PostId
order by eswch.ViewCount desc nulls last, eswch.Score desc nulls last, b.RankByPopularity
limit 100;