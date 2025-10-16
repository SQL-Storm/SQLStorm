-- {"query": "626.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1526} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(u.WebsiteUrl, 'no_website') as Website,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        row_number() over (partition by u.Id order by p.CreationDate desc nulls last) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.WebsiteUrl, u.Views, u.UpVotes, u.DownVotes
),
FilteredPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.ClosedDate,
        p.LastActivityDate,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        p.ContentLicense,
        u.DisplayName as OwnerDisplayName,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId,
        ph.UserDisplayName as EditorDisplayName,
        ph.Comment as HistoryComment,
        crt.Name as CloseReasonName
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10 -- Post Closed
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2) -- questions and answers only
),
AnswerScores as (
    select
        a.ParentId as QuestionId,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        count(a.Id) as TotalAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
UserBadgesWindow as (
    select
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        b.TagBased,
        row_number() over (partition by b.UserId order by b.Date desc) as BadgeRank
    from Badges b
),
TopBadges as (
    select
        ub.UserId,
        string_agg(ub.Name || ' (' || case ub.Class when 1 then 'Gold' when 2 then 'Silver' when 3 then 'Bronze' else 'Unknown' end || ')', ', ') as BadgesList
    from UserBadgesWindow ub
    where ub.BadgeRank <= 5
    group by ub.UserId
),
UserPostActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as Questions,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as Answers,
        count(distinct c.Id) as Comments,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        min(p.CreationDate) as FirstPostDate,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select
        pl.PostId as DuplicatePostId,
        pl.RelatedPostId as OriginalPostId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
),
ComplexTagAnalysis as (
    select
        p.Id as PostId,
        p.Title,
        p.Tags,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        count(*) over (partition by unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'))) as TagFrequency
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
RankedUserActivity as (
    select
        UserId,
        DisplayName,
        Reputation,
        Location,
        Website,
        QuestionCount,
        AnswerCount,
        CommentCount,
        BadgeCount,
        row_number() over (order by Reputation desc, QuestionCount desc) as UserRank
    from RecursiveUserActivity
)
select
    rua.UserRank,
    rua.DisplayName,
    rua.Reputation,
    coalesce(tb.BadgesList, 'No badges') as TopBadges,
    rua.QuestionCount,
    rua.AnswerCount,
    rua.CommentCount,
    rua.BadgeCount,
    upa.UpVotesGiven,
    upa.DownVotesGiven,
    upa.FirstPostDate,
    upa.LastPostDate,
    ds.TotalAnswers,
    ds.AvgAnswerScore,
    ds.MaxAnswerScore,
    ds.MinAnswerScore,
    dl.DuplicatePostId,
    dl.OriginalPostId,
    dl.DuplicateTitle,
    dl.OriginalTitle,
    dl.LinkCreationDate,
    cta.Tag,
    cta.TagFrequency
from RankedUserActivity rua
left join TopBadges tb on tb.UserId = rua.UserId
left join UserPostActivity upa on upa.UserId = rua.UserId
left join AnswerScores ds on ds.QuestionId in (
    select p.Id from Posts p where p.OwnerUserId = rua.UserId and p.PostTypeId = 1
)
left join DuplicateLinks dl on dl.DuplicatePostId in (
    select p.Id from Posts p where p.OwnerUserId = rua.UserId and p.PostTypeId = 1
)
left join ComplexTagAnalysis cta on cta.PostId in (
    select p.Id from Posts p where p.OwnerUserId = rua.UserId and p.PostTypeId = 1
)
where rua.UserRank <= 100
order by rua.Reputation desc, rua.QuestionCount desc, rua.AnswerCount desc
limit 200;