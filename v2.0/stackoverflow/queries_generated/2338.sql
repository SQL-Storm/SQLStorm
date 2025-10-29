-- {"query": "2338.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1592} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        u.Id as UserId,
        u.DisplayName,
        row_number() over (partition by t.Id order by u.Reputation desc nulls last) as UserRank
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 -- questions
),
FilteredUsers as (
    select
        UserId,
        DisplayName,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        sum(p.Score) as TotalScore,
        max(p.CreationDate) as LastPostDate,
        count(distinct b.Id) as BadgeCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id and b.Class = 1 -- Gold badges
    group by UserId, DisplayName
    having count(p.Id) > 10 and sum(p.Score) > 50
),
TopTags as (
    select
        TagName,
        sum(Count) as TotalTagCount
    from Tags
    group by TagName
    order by TotalTagCount desc
    limit 10
),
UserTagStats as (
    select
        rtc.TagName,
        rtc.UserId,
        rtc.DisplayName,
        rtc.Count as TagPostCount,
        fu.AnswerCount,
        fu.TotalScore,
        fu.BadgeCount,
        fu.LastPostDate,
        rank() over (partition by rtc.TagName order by fu.TotalScore desc) as UserScoreRank
    from RecursiveTagCounts rtc
    join FilteredUsers fu on fu.UserId = rtc.UserId
    where rtc.UserRank = 1
),
UserRecentActivity as (
    select
        u.Id,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        c.Id as CommentId,
        c.Text as CommentText,
        c.CreationDate as CommentDate,
        row_number() over (partition by u.Id order by p.LastActivityDate desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.PostId = p.Id
    where p.CreationDate > current_date - interval '90 days'
),
CorrelatedBadges as (
    select
        b.UserId,
        b.Name,
        count(*) as BadgeCount,
        max(b.Date) as LastBadgeDate,
        bool_or(b.TagBased = 1) as HasTagBased
    from Badges b
    group by b.UserId, b.Name
),
QuestionAnswerPair as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswererId,
        u.DisplayName as AnswererName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
DuplicateLinkedPosts as (
    select
        pl.PostId as DuplicatePostId,
        pl.RelatedPostId as OriginalPostId,
        pq.Title as OriginalTitle,
        pdu.DisplayName as DuplicateOwnerName,
        pq.OwnerUserId as OriginalOwnerId,
        pu.DisplayName as OriginalOwnerName
    from PostLinks pl
    join PostTypes pt on pt.Id = (select PostTypeId from Posts where Id = pl.PostId)
    join Posts pq on pq.Id = pl.RelatedPostId
    join Posts pd on pd.Id = pl.PostId
    left join Users pu on pu.Id = pq.OwnerUserId
    left join Users pdu on pdu.Id = pd.OwnerUserId
    where pl.LinkTypeId = 3 -- Duplicate linkType
),
CombinedSets as (
    select UserId, DisplayName, BadgeCount, LastPostDate from FilteredUsers
    union
    select UserId, DisplayName, BadgeCount, LastBadgeDate as LastPostDate from CorrelatedBadges
),
FinalSet as (
    select
        c.UserId,
        c.DisplayName,
        c.BadgeCount,
        c.LastPostDate,
        uts.TagName,
        uts.TagPostCount,
        uts.AnswerCount,
        uts.TotalScore,
        uts.UserScoreRank,
        qr.ActivityRank,
        qr.PostId,
        qr.PostTypeId,
        qr.Score as PostScore,
        qr.ViewCount,
        qr.Title,
        dlp.DuplicatePostId,
        dlp.OriginalPostId,
        dlp.OriginalTitle,
        dlp.DuplicateOwnerName,
        dlp.OriginalOwnerName
    from CombinedSets c
    left join UserTagStats uts on uts.UserId = c.UserId
    left join UserRecentActivity qr on qr.Id = c.UserId and qr.ActivityRank <= 5
    left join DuplicateLinkedPosts dlp on dlp.DuplicateOwnerName = c.DisplayName and dlp.DuplicatePostId = qr.PostId
    where c.BadgeCount > 0
)
select
    fs.UserId,
    fs.DisplayName,
    coalesce(fs.BadgeCount,0) as GoldBadgeCount,
    fs.LastPostDate,
    fs.TagName,
    fs.TagPostCount,
    fs.AnswerCount,
    fs.TotalScore,
    fs.UserScoreRank,
    fs.ActivityRank,
    fs.PostId,
    fs.PostTypeId,
    fs.PostScore,
    fs.ViewCount,
    left(fs.Title, 100) as ShortTitle,
    fs.DuplicatePostId,
    fs.OriginalPostId,
    left(fs.OriginalTitle, 100) as ShortOriginalTitle,
    fs.DuplicateOwnerName,
    fs.OriginalOwnerName,
    (
        select count(*)
        from Votes v
        where v.PostId = fs.PostId
        and v.VoteTypeId = 2 -- UpMod
        and v.CreationDate > current_date - interval '30 days'
    ) as RecentUpVotes,
    (
        select min(ph.CreationDate)
        from PostHistory ph
        where ph.PostId = fs.PostId
        and ph.PostHistoryTypeId in (10,11) -- Close and Reopen
    ) as FirstCloseReopenDate,
    case
        when fs.ViewCount is null or fs.ViewCount = 0 then null
        else round(cast(fs.Score as numeric) / fs.ViewCount, 6)
    end as ScoreViewRatio,
    case
        when fs.PostTypeId = 1 then concat('Q:', fs.ShortTitle)
        when fs.PostTypeId = 2 then concat('A:', fs.ShortTitle)
        else 'Other'
    end as PostLabel,
    case
        when fs.DuplicatePostId is not null then 'Duplicate'
        else 'Original or None'
    end as DuplicateStatus
from FinalSet fs
where fs.UserScoreRank <= 3
order by fs.TagPostCount desc, fs.TotalScore desc, fs.LastPostDate desc
limit 100;