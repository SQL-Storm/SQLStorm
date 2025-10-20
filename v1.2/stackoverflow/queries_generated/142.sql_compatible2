with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (order by t.Count desc) as Rank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = true then 1 else 0 end) as TagBasedBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
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
        p.Title,
        count(c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId in (1, 2)
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.Title
),
ClosedQuestions as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateOfTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        extract(epoch from (max(p.CreationDate) - min(p.CreationDate))) / 86400 as ActiveDays
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopTagsPerUser as (
    select
        ua.Id as UserId,
        tag,
        count(*) as TagUsageCount,
        row_number() over (partition by ua.Id order by count(*) desc) as TagRank
    from Users ua
    join Posts p on p.OwnerUserId = ua.Id and p.PostTypeId = 1 and p.Tags is not null
    cross join lateral (
        select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as tag
    ) t
    group by ua.Id, tag
),
UserTopTag as (
    select
        UserId,
        tag as TopTag
    from TopTagsPerUser
    where TagRank = 1
),
ComplexUserStats as (
    select
        uas.Id,
        uas.DisplayName,
        uas.QuestionsAsked,
        uas.AnswersGiven,
        uas.CommentsMade,
        uas.UpVotesGiven,
        uas.DownVotesGiven,
        coalesce(ub.GoldBadges, 0) as GoldBadges,
        coalesce(ub.SilverBadges, 0) as SilverBadges,
        coalesce(ub.BronzeBadges, 0) as BronzeBadges,
        coalesce(ub.TagBasedBadges, 0) as TagBasedBadges,
        ut.TopTag,
        case when uas.ActiveDays > 0 then (uas.QuestionsAsked + uas.AnswersGiven) * 1.0 / uas.ActiveDays else null end as PostsPerActiveDay,
        case when uas.AnswersGiven > 0 then (select avg(p.Score) from Posts p where p.OwnerUserId = uas.Id and p.PostTypeId = 2) else null end as AvgAnswerScore,
        case when uas.QuestionsAsked > 0 then (select avg(p.Score) from Posts p where p.OwnerUserId = uas.Id and p.PostTypeId = 1) else null end as AvgQuestionScore
    from UserActivitySummary uas
    left join UserBadgeStats ub on ub.UserId = uas.Id
    left join UserTopTag ut on ut.UserId = uas.Id
)
select
    c.Id as TagId,
    c.TagName,
    c.Count as TotalTagCount,
    c.AnswerCount,
    c.ViewCount,
    c.Score,
    c.Rank as TagPopularityRank,
    cu.Id as UserId,
    cu.DisplayName as UserName,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    cu.TagBasedBadges,
    cu.TopTag,
    cu.PostsPerActiveDay,
    cu.AvgAnswerScore,
    cu.AvgQuestionScore,
    dq.OriginalTitle as DuplicateQuestionTitle,
    dq.DuplicateOfTitle as DuplicateOfQuestionTitle,
    cq.CloseDate,
    cq.CloseReason,
    cq.ClosedByUserName,
    pa.RecentPostRank,
    pa.PrevScore,
    pa.NextScore,
    pa.CommentCount,
    pa.UpVotes,
    pa.DownVotes,
    case
        when pa.Score > 0 and pa.ViewCount > 1000 then 'High Impact'
        when pa.Score <= 0 and pa.ViewCount < 100 then 'Low Impact'
        else 'Medium Impact'
    end as ImpactCategory,
    case
        when pa.Tags is null then 'No Tags'
        else array_to_string(string_to_array(substring(pa.Tags from 2 for length(pa.Tags) - 2), '><'), ', ')
    end as ParsedTags
from RecursiveTagCounts c
left join ComplexUserStats cu on cu.TopTag = c.TagName
left join DuplicateLinks dq on dq.PostId = (
    select p.Id from Posts p where p.Tags like '%' || c.TagName || '%' limit 1
)
left join ClosedQuestions cq on cq.PostId = (
    select p.Id from Posts p where p.Tags like '%' || c.TagName || '%' and p.PostTypeId = 1 limit 1
)
left join PostActivityWindow pa on pa.OwnerUserId = cu.Id and pa.RecentPostRank = 1
where c.Rank <= 50
order by c.Rank, cu.GoldBadges desc nulls last, pa.Score desc nulls last;