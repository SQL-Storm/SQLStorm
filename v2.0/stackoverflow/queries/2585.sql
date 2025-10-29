-- {"query": "2585.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1453}
with RecursiveUserVotes as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreation,
        v.VoteTypeId,
        v.CreationDate as VoteDate,
        v.BountyAmount,
        row_number() over (partition by u.Id order by v.CreationDate desc) as rn
    from Users u
    join Votes v on v.UserId = u.Id
    join Posts p on p.Id = v.PostId
    where v.VoteTypeId in (2,3,8)
),
UserVoteStats as (
    select
        UserId,
        count(case when VoteTypeId = 2 then 1 end) as UpVotesReceived,
        count(case when VoteTypeId = 3 then 1 end) as DownVotesReceived,
        sum(coalesce(BountyAmount,0)) as TotalBountyGiven,
        min(PostCreation) as FirstPostDate,
        max(PostCreation) as LastPostDate,
        count(distinct PostId) as DistinctPostsVotedOn
    from RecursiveUserVotes
    group by UserId
),
PostAnswerAggregates as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        count(case when a.Score > 5 then 1 end) as HighScoreAnswers,
        avg(case when a.Score > 0 then a.Score end) as AvgPositiveScoreAnswers,
        sum(coalesce(a.CommentCount,0)) as TotalAnswerComments,
        max(a.CreationDate) as LatestAnswerDate
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId
),
UserBadgeRankings as (
    select
        UserId,
        sum(case when Class = 1 then 3 when Class = 2 then 2 when Class = 3 then 1 else 0 end) as BadgeWeight,
        count(*) as BadgesEarned,
        max(Date) as MostRecentBadgeDate,
        max(case when TagBased = true then 1 else 0 end) as HasTagBasedBadge
    from Badges
    group by UserId
),
RankedQuestions as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as QuestionRank
    from Posts p
    where p.PostTypeId = 1 and p.OwnerUserId is not null
),
CloseReasonStats as (
    select
        cht.Name as CloseReason,
        count(ph.Id) as CloseCount
    from PostHistory ph
    left join CloseReasonTypes cht on cast(ph.Comment as integer) = cht.Id
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
    group by cht.Name
),
Duplicates as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle,
        count(*) over(partition by pl.PostId) as DuplicateCount
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(uvs.UpVotesReceived,0) as UpVotesMade,
        coalesce(uvs.DownVotesReceived,0) as DownVotesMade,
        coalesce(uvs.TotalBountyGiven,0) as BountyGiven,
        coalesce(bad.BadgeWeight,0) as BadgeScore,
        coalesce(bad.BadgesEarned,0) as TotalBadges,
        coalesce(pa.HighScoreAnswers,0) as HighScoreAnswersByUser,
        coalesce(pa.AvgPositiveScoreAnswers,0) as AvgPositiveScoreAnswerScore,
        coalesce(pa.TotalAnswerComments,0) as TotalCommentsOnAnswers,
        coalesce(d.DuplicateCount,0) as TotalDuplicateQuestions,
        rqs.QuestionRank,
        coalesce(crs.CloseCount,0) as CloseVotesCast
    from Users u
    left join UserVoteStats uvs on uvs.UserId = u.Id
    left join UserBadgeRankings bad on bad.UserId = u.Id
    left join (
        select OwnerUserId, sum(HighScoreAnswers) as HighScoreAnswers, avg(AvgPositiveScoreAnswers) as AvgPositiveScoreAnswers,
               sum(TotalAnswerComments) as TotalAnswerComments
        from PostAnswerAggregates
        group by OwnerUserId
    ) pa on pa.OwnerUserId = u.Id
    left join (
        select ul.PostId, count(*) as DuplicateCount
        from Duplicates ul
        group by ul.PostId
    ) d on d.PostId = (
        select Id from Posts where OwnerUserId = u.Id and PostTypeId = 1 limit 1
    )
    left join RankedQuestions rqs on rqs.OwnerUserId = u.Id
    left join (
        select UserId, count(*) CloseCount
        from PostHistory 
        where PostHistoryTypeId = 10
        group by UserId
    ) crs on crs.UserId = u.Id
    where u.Reputation > 1000
)
select 
    uas.DisplayName,
    uas.Reputation,
    uas.UpVotesMade,
    uas.DownVotesMade,
    uas.BountyGiven,
    uas.BadgeScore,
    uas.TotalBadges,
    uas.HighScoreAnswersByUser,
    uas.AvgPositiveScoreAnswerScore,
    uas.TotalCommentsOnAnswers,
    uas.TotalDuplicateQuestions,
    uas.CloseVotesCast,
    case 
        when uas.BadgeScore > 20 then 'Expert'
        when uas.BadgeScore between 10 and 20 then 'Intermediate'
        else 'Novice'
    end as UserTier,
    concat(
        nullif(uas.DisplayName, ''), 
        ' | ',
        'Rep:' , cast(uas.Reputation as varchar),
        ' | Badges:' , cast(uas.TotalBadges as varchar),
        ' | Answers>5Score:' , cast(uas.HighScoreAnswersByUser as varchar)
    ) as SummaryString
from UserActivitySummary uas
where uas.BadgeScore is not null
group by
    uas.DisplayName,
    uas.Reputation,
    uas.UpVotesMade,
    uas.DownVotesMade,
    uas.BountyGiven,
    uas.BadgeScore,
    uas.TotalBadges,
    uas.HighScoreAnswersByUser,
    uas.AvgPositiveScoreAnswerScore,
    uas.TotalCommentsOnAnswers,
    uas.TotalDuplicateQuestions,
    uas.CloseVotesCast,
    case 
        when uas.BadgeScore > 20 then 'Expert'
        when uas.BadgeScore between 10 and 20 then 'Intermediate'
        else 'Novice'
    end,
    concat(
        nullif(uas.DisplayName, ''), 
        ' | ',
        'Rep:' , cast(uas.Reputation as varchar),
        ' | Badges:' , cast(uas.TotalBadges as varchar),
        ' | Answers>5Score:' , cast(uas.HighScoreAnswersByUser as varchar)
    )
order by uas.BadgeScore desc, uas.Reputation desc
limit 50;