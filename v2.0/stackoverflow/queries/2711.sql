with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
),
FilteredPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId
    from Posts p
    where p.PostTypeId in (1, 2) -- Questions or Answers
      and p.Score > 0
      and p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(a.TotalAnswerScore, 0) as TotalAnswerScore,
        coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
        q.AcceptedAnswerId
    from FilteredPosts q
    left join (
        select 
            p.ParentId,
            count(*) as AnswerCount,
            sum(p.Score) as TotalAnswerScore,
            max(p.Score) as MaxAnswerScore
        from FilteredPosts p
        where p.PostTypeId = 2
        group by p.ParentId
    ) a on q.Id = a.ParentId
    where q.PostTypeId = 1
),
UserActivityRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as PostsCount,
        count(distinct c.Id) as CommentsCount,
        row_number() over (order by count(distinct p.Id) desc, count(distinct c.Id) desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopActiveUsers as (
    select 
        UserId,
        DisplayName
    from UserActivityRanks
    where ActivityRank <= 50
),
LatestEdits as (
    select 
        ph.PostId,
        ph.UserId as EditorUserId,
        ph.CreationDate as EditDate,
        ph.PostHistoryTypeId,
        ph.Comment
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- title/body/tags edits
      and ph.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '6 months'
),
PostLinkAggregates as (
    select 
        pl.PostId,
        count(case when lt.Name = 'Linked' then 1 end) as LinkedCount,
        count(case when lt.Name = 'Duplicate' then 1 end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
QuestionsWithDupLinks as (
    select 
        p.Id,
        p.Title,
        coalesce(pll.LinkedCount, 0) as LinkedCount,
        coalesce(pll.DuplicateCount, 0) as DuplicateCount,
        coalesce(pa.AnswerCount, 0) as AnswerCount,
        coalesce(pa.TotalAnswerScore, 0) as TotalAnswerScore,
        coalesce(pa.MaxAnswerScore, 0) as MaxAnswerScore,
        u.DisplayName as OwnerName,
        arr.ActivityRank,
        string_agg(distinct concat('Badge:', rtrim(b.BadgeName), '(', b.Class, ')'), ', ') filter (where b.Class is not null) as Badges
    from FilteredPosts p
    left join PostLinkAggregates pll on p.Id = pll.PostId
    left join PostAnswerStats pa on p.Id = pa.QuestionId
    left join Users u on p.OwnerUserId = u.Id
    left join UserActivityRanks arr on u.Id = arr.UserId
    left join RecursiveUserBadges b on b.UserId = u.Id and b.BadgeRank <= 3
    where p.PostTypeId = 1
      and (coalesce(pll.DuplicateCount, 0) > 0 or coalesce(pll.LinkedCount, 0) > 3)
      and arr.ActivityRank <= 100
    group by p.Id, p.Title, coalesce(pll.LinkedCount, 0), coalesce(pll.DuplicateCount, 0), coalesce(pa.AnswerCount, 0), coalesce(pa.TotalAnswerScore, 0), coalesce(pa.MaxAnswerScore, 0), u.DisplayName, arr.ActivityRank
),
AnswerVotesStats as (
    select
        a.Id as AnswerId,
        count(case when vt.Name = 'UpMod' then v.Id end) as UpVotes,
        count(case when vt.Name = 'DownMod' then v.Id end) as DownVotes,
        sum(case when vt.Name = 'UpMod' then 1 when vt.Name = 'DownMod' then -1 else 0 end) as VoteScore,
        max(v.CreationDate) as LastVoteDate
    from FilteredPosts a
    left join Votes v on v.PostId = a.Id
    left join VoteTypes vt on v.VoteTypeId = vt.Id
    where a.PostTypeId = 2
    group by a.Id
),
FinalRanks as (
    select
        qd.Id as QuestionId,
        qd.Title,
        qd.LinkedCount,
        qd.DuplicateCount,
        qd.AnswerCount,
        qd.TotalAnswerScore,
        qd.MaxAnswerScore,
        qd.OwnerName,
        qd.ActivityRank,
        qd.Badges,
        a.UpVotes,
        a.DownVotes,
        a.VoteScore,
        row_number() over (
            order by
                qd.AnswerCount desc,
                qd.TotalAnswerScore desc,
                a.VoteScore desc,
                qd.LinkedCount desc
        ) as RankScore
    from QuestionsWithDupLinks qd
    left join Posts p on qd.Id = p.Id
    left join AnswerVotesStats a on a.AnswerId = p.AcceptedAnswerId
)
select
    fr.RankScore,
    fr.QuestionId,
    substr(fr.Title, 1, 100) as ShortTitle,
    fr.OwnerName,
    fr.AnswerCount,
    fr.TotalAnswerScore,
    fr.MaxAnswerScore,
    fr.LinkedCount,
    fr.DuplicateCount,
    fr.UpVotes,
    fr.DownVotes,
    fr.VoteScore,
    fr.Badges,
    case 
        when fr.DuplicateCount > 0 then 'Has duplicates'
        when fr.LinkedCount > 5 then 'Highly linked'
        else 'Normal'
    end as QuestionStatus,
    u.Reputation,
    u.Views,
    u.UpVotes as UserUpVotes,
    u.DownVotes as UserDownVotes,
    u.Location,
    concat('https://stackoverflow.com/questions/', fr.QuestionId) as QuestionUrl
from FinalRanks fr
join Users u on u.Id = (
    select Id from Users uu where uu.DisplayName = fr.OwnerName limit 1
)
where fr.RankScore <= 50
order by fr.RankScore, fr.TotalAnswerScore desc, fr.VoteScore desc;