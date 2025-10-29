-- {"query": "2616.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1515} 
with RecursiveUserBadges AS (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
),
TopBadgeUsers AS (
    select
        UserId,
        DisplayName,
        Reputation,
        BadgeName,
        BadgeClass
    from RecursiveUserBadges
    where BadgeRank <= 3
),
PostScores AS (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        coalesce(p.Title, '') as Title,
        coalesce(p.Tags, '') as Tags,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        coalesce(pl.LinkTypeId, 0) as LinkTypeId,
        pl.RelatedPostId
    from Posts p
    left join PostLinks pl on p.Id = pl.PostId
),
UserActivity AS (
    select
        u.Id,
        u.DisplayName,
        count(distinct ph.Id) as EditsCount,
        count(distinct coalesce(p.Id,0)) as PostsCount,
        count(distinct coalesce(c.Id,0)) as CommentsCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesGiven,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesGiven
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
RecursivePostLinks AS (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        1 as LinkDepth
    from PostLinks pl
    where pl.LinkTypeId = 3 -- duplicates

    union all

    select
        rpl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        rpl.LinkDepth + 1
    from RecursivePostLinks rpl
    join PostLinks pl on rpl.RelatedPostId = pl.PostId
    where pl.LinkTypeId = 3 and rpl.LinkDepth < 3
),
DuplicatesSummary AS (
    select
        PostId,
        count(distinct RelatedPostId) as DuplicateCount,
        max(LinkDepth) as MaxDuplicateDepth
    from RecursivePostLinks
    group by PostId
),
QuestionActivity AS (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        d.DuplicateCount,
        d.MaxDuplicateDepth,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join DuplicatesSummary d on p.Id = d.PostId
    where p.PostTypeId = 1
),
ComplexQuestions AS (
    select
        q.*,
        case when q.DuplicateCount is null then 0 else q.DuplicateCount end as EffectiveDuplicateCount,
        (select count(*) from Posts a where a.ParentId = q.Id) as AnswerCount,
        (select avg(s.Score) from Posts s where s.ParentId = q.Id) as AvgAnswerScore,
        (select max(s.Score) from Posts s where s.ParentId = q.Id) as MaxAnswerScore,
        (select count(*) from Comments c where c.PostId = q.Id and c.CreationDate > q.CreationDate) as CommentsAfterQuestion,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 3) as DownVotes,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 5) as Favorites
    from QuestionActivity q
    where q.RecentRank <= 5
),
FinalResult AS (
    select
        cq.Id,
        cq.Title,
        cq.Tags,
        cq.CreationDate,
        cq.Score,
        cq.ViewCount,
        cq.OwnerUserId,
        cq.OwnerDisplayName,
        cq.EffectiveDuplicateCount,
        cq.DuplicateCount,
        cq.MaxDuplicateDepth,
        cq.AnswerCount,
        cq.AvgAnswerScore,
        cq.MaxAnswerScore,
        cq.CommentsAfterQuestion,
        cq.UpVotes,
        cq.DownVotes,
        cq.Favorites,
        ua.PostsCount,
        ua.EditsCount,
        ua.CommentsCount,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        tb.BadgeName,
        tb.BadgeClass,
        dense_rank() over (partition by cq.OwnerUserId order by cq.Score desc) as ScoreRank,
        dense_rank() over (order by cq.ViewCount desc) as ViewRank,
        case when cq.SCORE > 0 then 1 else 0 end as PositiveScoreFlag,
        (length(coalesce(cq.Title, '')) - length(replace(coalesce(lower(cq.Title),''), 'sql', ''))) / 3 as SqlKeywordCount,
        substring(coalesce(cq.Tags, '') from '%<sql>%') is not null as HasSqlTag
    from ComplexQuestions cq
    left join UserActivity ua on ua.Id = cq.OwnerUserId
    left join TopBadgeUsers tb on tb.UserId = cq.OwnerUserId
)
select distinct
    Id,
    Title,
    Tags,
    CreationDate,
    Score,
    ViewCount,
    OwnerUserId,
    OwnerDisplayName,
    EffectiveDuplicateCount,
    MaxDuplicateDepth,
    AnswerCount,
    coalesce(AvgAnswerScore,0) as AvgAnswerScore,
    MaxAnswerScore,
    CommentsAfterQuestion,
    UpVotes,
    DownVotes,
    Favorites,
    PostsCount,
    EditsCount,
    CommentsCount,
    UpVotesGiven,
    DownVotesGiven,
    BadgeName,
    BadgeClass,
    ScoreRank,
    ViewRank,
    PositiveScoreFlag,
    SqlKeywordCount,
    HasSqlTag
from FinalResult
where (BadgeClass = 1 or BadgeClass is null)
and Score > 5
and (Tags like '%<sql>%' or Tags like '%<database>%')
order by ViewRank, ScoreRank;