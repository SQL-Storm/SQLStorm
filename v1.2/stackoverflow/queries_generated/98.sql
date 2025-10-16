-- {"query": "98.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1702} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id > r.Id
    where t2.IsModeratorOnly = 0 and t2.IsRequired = 0 and not t2.TagName = any(r.Path)
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        row_number() over (partition by u.Location order by u.Reputation desc) as RankByLocation,
        avg(u.Reputation) over (partition by u.Location) as AvgReputationByLocation,
        count(*) over (partition by u.Location) as UsersInLocation
    from Users u
    where u.Location is not null
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId is not null then 1 else 0 end) as AnswersWithOwner,
        sum(case when a.Score > q.Score then 1 else 0 end) as AnswersBetterThanQuestion
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        coalesce(sum(v.BountyAmount),0) as TotalBountyGiven,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopTagsByActivity as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
        count(*) as PostCount,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    order by PostCount desc
    limit 50
),
DuplicateLinkAnalysis as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate,
        u.DisplayName as PostOwner,
        u2.DisplayName as RelatedPostOwner
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    left join Users u on u.Id = p1.OwnerUserId
    left join Users u2 on u2.Id = p2.OwnerUserId
    where pl.LinkTypeId = 3
),
UserBadgeRankings as (
    select
        ubc.UserId,
        ubc.Class,
        ubc.BadgeCount,
        rank() over (partition by ubc.Class order by ubc.BadgeCount desc) as BadgeRank
    from UserBadgeCounts ubc
),
UserWithBadgesAndActivity as (
    select
        uas.UserId,
        uas.DisplayName,
        uas.QuestionsPosted,
        uas.AnswersPosted,
        uas.CommentsMade,
        uas.UpVotesGiven,
        uas.DownVotesGiven,
        uas.TotalBountyGiven,
        ubc.Class,
        ubc.BadgeCount,
        ubr.BadgeRank
    from UserActivitySummary uas
    left join UserBadgeCounts ubc on ubc.UserId = uas.UserId
    left join UserBadgeRankings ubr on ubr.UserId = uas.UserId and ubr.Class = ubc.Class
)
select
    pqs.QuestionId,
    pqs.Title,
    pqs.QuestionCreation,
    pqs.QuestionScore,
    pqs.ViewCount,
    pqs.AnswerCount,
    pqs.MaxAnswerScore,
    pqs.AvgAnswerScore,
    pqs.AnswersWithOwner,
    pqs.AnswersBetterThanQuestion,
    pcr.CloseReasonName,
    pcr.CloseDate,
    utba.Tag,
    utba.PostCount as TagPostCount,
    utba.AvgScore as TagAvgScore,
    utba.MaxScore as TagMaxScore,
    dla.PostTitle as DuplicatePostTitle,
    dla.RelatedPostTitle as DuplicateRelatedPostTitle,
    dla.CreationDate as DuplicateLinkDate,
    dla.PostOwner as DuplicatePostOwner,
    dla.RelatedPostOwner as DuplicateRelatedPostOwner,
    uwb.DisplayName as UserDisplayName,
    uwb.QuestionsPosted,
    uwb.AnswersPosted,
    uwb.CommentsMade,
    uwb.UpVotesGiven,
    uwb.DownVotesGiven,
    uwb.TotalBountyGiven,
    uwb.Class as BadgeClass,
    uwb.BadgeCount,
    uwb.BadgeRank
from PostAnswerStats pqs
left join PostCloseReasons pcr on pcr.PostId = pqs.QuestionId
left join lateral (
    select Tag, PostCount, AvgScore, MaxScore
    from TopTagsByActivity t
    where pqs.Tags like '%' || t.Tag || '%'
    order by PostCount desc
    limit 1
) utba on true
left join lateral (
    select *
    from DuplicateLinkAnalysis dla
    where dla.PostId = pqs.QuestionId
    order by dla.CreationDate desc
    limit 1
) dla on true
left join lateral (
    select *
    from UserWithBadgesAndActivity uwb
    where uwb.UserId = (
        select OwnerUserId from Posts where Id = pqs.QuestionId
    )
) uwb on true
where pqs.AnswerCount > 5
  and (pqs.MaxAnswerScore > pqs.QuestionScore or pqs.AnswersBetterThanQuestion > 0)
  and (pcr.CloseDate is null or pcr.CloseDate > pqs.QuestionCreation)
order by pqs.ViewCount desc, pqs.QuestionScore desc
limit 100;