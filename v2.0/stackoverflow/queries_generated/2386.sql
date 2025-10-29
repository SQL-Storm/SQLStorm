-- {"query": "2386.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1669} 
with RecursiveBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        count(*) over (partition by u.Id) as TotalBadges,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.Class is not null
),
BadgeRanks as (
    select distinct
        UserId,
        DisplayName,
        Class,
        BadgeName,
        TotalBadges
    from RecursiveBadges
    where rn = 1
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        coalesce(q.AcceptedAnswerId, -1) as AcceptedAnswerId,
        count(a.Id) filter (where a.CreationDate is not null) as AnswersCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Score > 0 then 1 else 0 end) as PositiveScoreAnswers,
        sum(a.ViewCount) as AnswerViewCountSum
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.AcceptedAnswerId
),
Ranking as (
    select
        PostAnswerStats.*,
        dense_rank() over (order by AnswersCount desc, MaxAnswerScore desc, QuestionCreation) as RankByAnswers,
        dense_rank() over (order by AvgAnswerScore desc nulls last) as RankByAvgScore
    from PostAnswerStats
),
LatestPostHistory as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate
    from PostHistory ph
    order by ph.PostId, ph.CreationDate desc
),
DuplicatedPosts as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        p.Title as PostTitle,
        rp.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p on p.Id = pl.PostId
    join Posts rp on rp.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- duplicates
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(c.Id) as CommentsCount,
        sum(v.VoteTypeId = 2)::int as UpVotesReceived,
        sum(v.VoteTypeId = 3)::int as DownVotesReceived,
        max(p.CreationDate) as LastPostDate,
        min(u.CreationDate) as UserCreationDate,
        (extract(epoch from now()) - extract(epoch from u.CreationDate)) / 86400 as UserAgeDays
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopUsersWithBadges as (
    select
        ua.*,
        coalesce(br.TotalBadges, 0) as TotalBadges,
        case when br.Class = 1 then 'Gold'
             when br.Class = 2 then 'Silver'
             when br.Class = 3 then 'Bronze'
             else 'None' end as TopBadgeClass,
        br.BadgeName as TopBadgeName
    from UserActivity ua
    left join BadgeRanks br on br.UserId = ua.UserId
    where ua.QuestionsCount > 0 or ua.AnswersCount > 0
),
QuestionTags as (
    select
        p.Id as QuestionId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagPopularQuestions as (
    select
        qt.Tag,
        count(distinct qt.QuestionId) as QuestionCount,
        avg(r.AnswersCount) as AvgAnswers,
        max(r.MaxAnswerScore) as MaxAnswerScore,
        min(r.QuestionCreation) as OldestQuestionDate
    from QuestionTags qt
    join Ranking r on r.QuestionId = qt.QuestionId
    group by qt.Tag
    having count(distinct qt.QuestionId) > 100
),
ComplexUserScore as (
    select
        tu.UserId,
        tu.DisplayName,
        tu.QuestionsCount,
        tu.AnswersCount,
        tu.CommentsCount,
        tu.UpVotesReceived,
        tu.DownVotesReceived,
        tu.TotalBadges,
        ( (tu.UpVotesReceived * 2)
          + (tu.AnswersCount * 5)
          + (tu.QuestionsCount * 3)
          + (tu.CommentsCount)
          + (tu.TotalBadges * 10)
          - (cu.RecentDownVotes * 3)
        ) as UserInfluenceScore
    from TopUsersWithBadges tu
    left join (
        select
            v.UserId,
            count(*) filter (where v.VoteTypeId = 3) as RecentDownVotes
        from Votes v
        where v.CreationDate > now() - interval '30 days'
        group by v.UserId
    ) cu on cu.UserId = tu.UserId
)
select
    r.RankByAnswers,
    r.RankByAvgScore,
    r.QuestionId,
    r.Title,
    r.AnswersCount,
    r.MaxAnswerScore,
    r.AvgAnswerScore,
    r.AcceptedAnswerId,
    case
        when r.AcceptedAnswerId is null then 'No'
        else 'Yes'
    end as HasAcceptedAnswer,
    dup.PostTitle as DuplicateOf,
    ts.Tag,
    ts.QuestionCount,
    ts.AvgAnswers as AvgAnswersForTag,
    ts.MaxAnswerScore as MaxAnswerScoreForTag,
    ts.OldestQuestionDate as TagOldestQuestion,
    cu.UserInfluenceScore,
    cu.DisplayName as TopContributor,
    ph.PostHistoryTypeId,
    pt.Name as LastPostHistoryType,
    latestPh.CreationDate as LastHistoryEditDate,
    u.Reputation,
    u.CreationDate as UserJoined,
    u.Location,
    case when u.WebsiteUrl is not null and length(u.WebsiteUrl) > 0 then true else false end as HasWebsite,
    concat_ws(' - ',
        substring(u.AboutMe from 1 for 100),
        concat('Reputation: ', u.Reputation),
        coalesce(u.Location, 'Unknown Location')
    ) as UserSummary
from Ranking r
left join DuplicatedPosts dup on dup.PostId = r.QuestionId
left join QuestionTags qt on qt.QuestionId = r.QuestionId
left join TagPopularQuestions ts on ts.Tag = qt.Tag
left join ComplexUserScore cu on cu.UserId = r.OwnerUserId
left join Users u on u.Id = r.OwnerUserId
left join LatestPostHistory latestPh on latestPh.PostId = r.QuestionId
left join PostHistoryTypes pt on pt.Id = latestPh.PostHistoryTypeId
where r.AnswersCount >= 5 and (r.AvgAnswerScore > 1.5 or r.MaxAnswerScore > 10)
order by r.RankByAnswers, r.MaxAnswerScore desc
limit 100;