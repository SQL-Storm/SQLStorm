-- {"query": "488.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1440} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.TagBased = 0 or b.TagBased is null
),
UserBadgeSummary as (
    select
        UserId,
        count(distinct case when Class = 1 then BadgeName end) as GoldBadges,
        count(distinct case when Class = 2 then BadgeName end) as SilverBadges,
        count(distinct case when Class = 3 then BadgeName end) as BronzeBadges,
        max(Date) as LastBadgeDate
    from RecursiveUserBadges
    group by UserId
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate as QuestionDate,
        count(a.Id) as AnswerCount,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        max(coalesce(a.Score,0)) as MaxAnswerScore,
        sum(case when a.OwnerUserId = q.OwnerUserId then 1 else 0 end) as AnswersByOwner
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.OwnerUserId, q.Title, q.CreationDate
),
PostLinkDuplicates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        bool_or(lt.Name = 'Duplicate') as HasDuplicateLink
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
QuestionCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as CloseReasonId,
        max(ph.CreationDate) as CloseDate
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
UserRecentActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        max(p.LastActivityDate) as LastPostActivity,
        max(c.CreationDate) as LastCommentDate,
        max(ph.CreationDate) as LastEditDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopQuestionsWithAnswers as (
    select
        qas.QuestionId,
        qas.Title,
        qas.AnswerCount,
        qas.AvgAnswerScore,
        qas.MaxAnswerScore,
        qas.AnswersByOwner,
        pls.DuplicateCount,
        pls.HasDuplicateLink,
        qci.CloseReasonId,
        qci.CloseDate,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ura.LastPostActivity,
        ura.LastCommentDate,
        ura.LastEditDate,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.Location,
        u.AboutMe,
        -- Complex string expression: concatenate tags from Tags column (assume tags are in format '<tag1><tag2>...')
        regexp_replace(qas.Title, '[^a-zA-Z0-9\s]', '', 'g') as CleanTitle,
        length(qas.Title) as TitleLength
    from PostAnswerStats qas
    left join PostLinkDuplicates pls on qas.QuestionId = pls.PostId
    left join QuestionCloseInfo qci on qas.QuestionId = qci.PostId
    left join UserBadgeSummary ubs on qas.OwnerUserId = ubs.UserId
    left join Users u on qas.OwnerUserId = u.Id
    left join UserRecentActivity ura on u.Id = ura.UserId
    where qas.AnswerCount > 0
),
RankedQuestions as (
    select
        *,
        rank() over (order by AnswerCount desc, AvgAnswerScore desc, Reputation desc nulls last) as RankByAnswers,
        dense_rank() over (partition by (case when CloseReasonId is null then 0 else 1 end) order by MaxAnswerScore desc) as RankByMaxAnswerScoreByCloseStatus
    from TopQuestionsWithAnswers
),
CorrelatedUserVotes as (
    select
        u.Id as UserId,
        (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 2) as UpVotesCast,
        (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 3) as DownVotesCast,
        (select count(distinct p.Id) from Posts p where p.OwnerUserId = u.Id and p.Score > 10) as HighScorePosts
    from Users u
)
select
    rq.QuestionId,
    rq.CleanTitle,
    rq.TitleLength,
    rq.AnswerCount,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    rq.DuplicateCount,
    rq.HasDuplicateLink,
    rq.CloseReasonId,
    rq.CloseDate,
    rq.GoldBadges,
    rq.SilverBadges,
    rq.BronzeBadges,
    rq.LastPostActivity,
    rq.LastCommentDate,
    rq.LastEditDate,
    rq.Reputation,
    rq.UserCreationDate,
    coalesce(rq.Location, 'Unknown') as Location,
    case
        when rq.AboutMe is null then 'No About Me'
        when length(rq.AboutMe) > 100 then substring(rq.AboutMe from 1 for 100) || '...'
        else rq.AboutMe
    end as AboutMeSnippet,
    cuv.UpVotesCast,
    cuv.DownVotesCast,
    cuv.HighScorePosts,
    rq.RankByAnswers,
    rq.RankByMaxAnswerScoreByCloseStatus
from RankedQuestions rq
left join CorrelatedUserVotes cuv on rq.OwnerUserId = cuv.UserId
where (rq.GoldBadges + rq.SilverBadges + rq.BronzeBadges) > 0
  and (rq.CloseReasonId is null or rq.CloseReasonId::int not in (101,102))
order by rq.RankByAnswers asc, rq.AvgAnswerScore desc
limit 100;