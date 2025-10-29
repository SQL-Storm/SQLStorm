-- {"query": "2305.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1761} 
with RecursivePopularPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        ROW_NUMBER() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn
    from 
        Posts p
    where
        p.Score > 20 and p.ViewCount > 1000 and p.PostTypeId in (1,2)
),
RecentUserBadges as (
    select 
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        row_number() over (partition by b.UserId order by b.Date desc) as badge_rn
    from Badges b
    where b.Date > (current_timestamp - interval '90 days')
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from
        Users u
        left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
PostCloseReasonSummary as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from
        PostHistory ph
        join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
        join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where
        ph.PostHistoryTypeId = 10 and ph.Comment ~ '^\d+$'
    group by ph.PostId, crt.Name
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(*) filter (where v.VoteTypeId = 2) as TotalUpVotesOnAnswers,
        count(*) filter (where v.VoteTypeId = 3) as TotalDownVotesOnAnswers,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore
    from Posts p
    left join Votes v on p.Id = v.PostId
    where p.PostTypeId = 2
    group by p.ParentId
),
UserActivityWin as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as PostCount,
        count(distinct c.Id) as CommentCount,
        count(distinct case when v.VoteTypeId = 2 then v.Id end) as UpVotesGiven,
        count(distinct case when v.VoteTypeId = 3 then v.Id end) as DownVotesGiven,
        row_number() over (partition by u.Id order by max(p.CreationDate) desc nulls last) as LastPostRecencyRank
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    left join Votes v on u.Id = v.UserId
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select 
        pl.PostId,
        array_agg(distinct p2.Title) as DuplicateTitles,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    join Posts p2 on pl.RelatedPostId = p2.Id
    where pl.LinkTypeId = 3
    group by pl.PostId
),
UserTaggedPosts as (
    select 
        p.OwnerUserId,
        unnest(string_to_array(trim(both '<>' from p.Tags), '><')) as Tag,
        count(*) as TagPostCount
    from Posts p
    where p.PostTypeId = 1 and p.OwnerUserId is not null
    group by p.OwnerUserId, Tag
),
TopUserTags as (
    select
        utp.OwnerUserId,
        utp.Tag,
        utp.TagPostCount,
        rank() over (partition by utp.OwnerUserId order by utp.TagPostCount desc) as rnk
    from 
        UserTaggedPosts utp
),
FilteredBestTags as (
    select OwnerUserId, Tag, TagPostCount
    from TopUserTags
    where rnk <= 3
),
PostsWithHistoricalEdits as (
    select 
        p.Id as PostId,
        p.OwnerUserId,
        ph.PostHistoryTypeId,
        pht.Name as HistoryTypeName,
        ph.CreationDate as EditDate,
        row_number() over (partition by p.Id order by ph.CreationDate) as EditNumber
    from Posts p
    left join PostHistory ph on p.Id = ph.PostId
    left join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
),
RecentEdits as (
    select 
        PostId,
        OwnerUserId,
        count(*) filter (where EditDate > current_timestamp - interval '30 days') as RecentEditCount,
        max(EditDate) as LastEditDate
    from PostsWithHistoricalEdits
    group by PostId, OwnerUserId
)

select 
    p.Id as QuestionId,
    coalesce(p.Title, '[No Title]') as QuestionTitle,
    p.Score as QuestionScore,
    p.ViewCount,
    coalesce(ans.AvgAnswerScore, 0)::numeric(10,2) as AvgAnswerScore,
    coalesce(ans.MaxAnswerScore, 0) as MaxAnswerScore,
    u.DisplayName as OwnerName,
    u.Reputation,
    u.CreationDate as UserCreationDate,
    u.LastAccessDate,
    u.Location,
    coalesce(ubs.GoldBadges,0) as GoldBadges,
    coalesce(ubs.SilverBadges,0) as SilverBadges,
    coalesce(ubs.BronzeBadges,0) as BronzeBadges,
    pcr.CloseReason,
    pcr.CloseCount,
    dl.DuplicateCount,
    array_to_string(dl.DuplicateTitles, ', ') as DuplicateTitles,
    COALESCE(fe.RecentEditCount,0) as RecentEditCount,
    fe.LastEditDate,
    array_to_string(array_agg(distinct ft.Tag), ', ') as TopTags,
    ua.PostCount,
    ua.CommentCount,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ua.LastPostRecencyRank,
    rank() over (order by p.Score desc, p.ViewCount desc) as OverallRank

from RecursivePopularPosts p

left join Users u on p.OwnerUserId = u.Id
left join AnswerStats ans on ans.QuestionId = p.Id
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join PostCloseReasonSummary pcr on p.Id = pcr.PostId
left join DuplicateLinks dl on p.Id = dl.PostId
left join RecentEdits fe on p.Id = fe.PostId
left join FilteredBestTags ft on ft.OwnerUserId = u.Id
left join UserActivityWin ua on ua.UserId = u.Id

where 
    (p.CreationDate > current_date - interval '3 year'
    or p.Score > 50)
    and (p.ViewCount > 1000 or ans.MaxAnswerScore > 10)

group by
    p.Id, p.Title, p.Score, p.ViewCount, ans.AvgAnswerScore, ans.MaxAnswerScore, 
    u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location,
    ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges,
    pcr.CloseReason, pcr.CloseCount,
    dl.DuplicateCount, dl.DuplicateTitles,
    fe.RecentEditCount, fe.LastEditDate,
    ua.PostCount, ua.CommentCount, ua.UpVotesGiven, ua.DownVotesGiven, ua.LastPostRecencyRank

having 
    (coalesce(ubs.GoldBadges, 0) + coalesce(ubs.SilverBadges, 0)) > 0
    or p.Score > 100

order by OverallRank limit 50;