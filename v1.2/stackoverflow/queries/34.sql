with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = true

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        r.Level + 1,
        r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on not t.Id = any(r.Path)
    where t.IsRequired = true and t.Count < r.Count
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        coalesce(sum(case when b.TagBased = true then 1 else 0 end),0) as TagBasedBadges,
        row_number() over (order by u.Reputation desc) as RepRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.ClosedDate,
        p.Title,
        count(c.Id) over (partition by p.Id) as CommentCountWindow,
        sum(case when v.VoteTypeId = 2 and v.CreationDate >= p.CreationDate and v.CreationDate < p.CreationDate + interval '30 days' then 1 else 0 end) over () as UpVotes30Days,
        sum(case when v.VoteTypeId = 3 and v.CreationDate >= p.CreationDate and v.CreationDate < p.CreationDate + interval '30 days' then 1 else 0 end) over () as DownVotes30Days
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        q.AcceptedAnswerId,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsPosted,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesGiven,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesGiven,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
ComplexPostStats as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        case
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Answered'
            else 'Open'
        end as PostStatus,
        length(coalesce(p.Body, '')) as BodyLength,
        strpos(lower(coalesce(p.Body, '')), 'sql') as SqlKeywordPos,
        (select count(*) from Comments c where c.PostId = p.Id and c.CreationDate > p.CreationDate) as CommentsAfterCreation,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2 and v.CreationDate > p.CreationDate) as UpVotesAfterCreation
    from Posts p
    where p.PostTypeId in (1,2)
)
select
    ubs.UserId,
    ubs.DisplayName,
    ubs.RepRank,
    uas.QuestionsPosted,
    uas.AnswersPosted,
    uas.CommentsMade,
    uas.UpVotesGiven,
    uas.DownVotesGiven,
    coalesce(ps.PostCount, 0) as TotalPosts,
    coalesce(ps.AvgScore, 0) as AvgPostScore,
    coalesce(ps.MaxScore, 0) as MaxPostScore,
    coalesce(ps.MinScore, 0) as MinPostScore,
    coalesce(ps.AvgBodyLength, 0) as AvgBodyLength,
    coalesce(ps.SqlKeywordCount, 0) as PostsContainingSql,
    coalesce(dl.DuplicateCount, 0) as DuplicateLinksCount,
    string_agg(distinct rt.TagName, ', ') as RequiredTagsUsed,
    max(pa.CreationDate) as LastPostDate,
    max(pa.Score) as HighestScorePost,
    max(pa.ViewCount) as HighestViewCountPost
from UserBadgeStats ubs
left join UserActivitySummary uas on uas.UserId = ubs.UserId
left join (
    select
        OwnerUserId,
        count(*) as PostCount,
        avg(Score) as AvgScore,
        max(Score) as MaxScore,
        min(Score) as MinScore,
        avg(length(coalesce(Body, ''))) as AvgBodyLength,
        sum(case when lower(coalesce(Body, '')) like '%sql%' then 1 else 0 end) as SqlKeywordCount
    from Posts
    where OwnerUserId is not null
    group by OwnerUserId
) ps on ps.OwnerUserId = ubs.UserId
left join (
    select
        p.OwnerUserId,
        count(distinct pl.Id) as DuplicateCount
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    where p.OwnerUserId is not null
    group by p.OwnerUserId
) dl on dl.OwnerUserId = ubs.UserId
left join RecursiveTagHierarchy rt on rt.Id = any (
    select cast(unnested as integer) from (
        select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as unnested
        from Posts p where p.OwnerUserId = ubs.UserId limit 1
    ) s
)
left join Posts pa on pa.OwnerUserId = ubs.UserId
group by
    ubs.UserId,
    ubs.DisplayName,
    ubs.RepRank,
    uas.QuestionsPosted,
    uas.AnswersPosted,
    uas.CommentsMade,
    uas.UpVotesGiven,
    uas.DownVotesGiven,
    ps.PostCount,
    ps.AvgScore,
    ps.MaxScore,
    ps.MinScore,
    ps.AvgBodyLength,
    ps.SqlKeywordCount,
    dl.DuplicateCount
order by ubs.RepRank
limit 100;