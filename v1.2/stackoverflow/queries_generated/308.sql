-- {"query": "308.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1318} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date >= current_date - interval '365 days'
),
TopUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(v.VoteCount), 0) as TotalVotes,
        max(p.Score) as MaxPostScore,
        min(p.CreationDate) as FirstPostDate,
        max(p.LastActivityDate) as LastActivityDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod and DownMod
        group by PostId
    ) v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(distinct p.Id) filter (where p.PostTypeId = 1) > 10
       and count(distinct p.Id) filter (where p.PostTypeId = 2) > 10
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(c.Id) over (partition by p.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) over (partition by p.Id) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) over (partition by p.Id) as DownVotes,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    where p.CreationDate >= current_date - interval '180 days'
),
DuplicateQuestions as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle,
        p1.CreationDate as DuplicateCreation,
        p2.CreationDate as OriginalCreation
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3 -- Duplicate
),
UserTagExpertise as (
    select
        u.Id as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        count(*) as PostsCount,
        avg(p.Score) as AvgScore
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
    group by u.Id, Tag
),
RankedUserTags as (
    select
        UserId,
        Tag,
        PostsCount,
        AvgScore,
        rank() over (partition by UserId order by PostsCount desc, AvgScore desc) as TagRank
    from UserTagExpertise
),
RecentPostHistoryEdits as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment,
        ph.Text,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as EditRank
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
      and ph.CreationDate >= current_date - interval '90 days'
)
select
    tu.Id as UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalVotes,
    tu.MaxPostScore,
    tu.FirstPostDate,
    tu.LastActivityDate,
    ruw.PostId,
    ruw.PostTypeId,
    ruw.Score as PostScore,
    ruw.CommentCount,
    ruw.UpVotes,
    ruw.DownVotes,
    dt.DuplicateQuestionId,
    dt.OriginalQuestionId,
    dt.DuplicateTitle,
    dt.OriginalTitle,
    dt.DuplicateCreation,
    dt.OriginalCreation,
    rut.Tag as TopTag,
    rut.PostsCount as TagPostsCount,
    rut.AvgScore as TagAvgScore,
    ph.EditsCount,
    ph.LastEditDate,
    rub.BadgeName,
    rub.Class as BadgeClass
from TopUsers tu
left join UserActivityWindow ruw on ruw.UserId = tu.Id and ruw.RecentPostRank = 1
left join DuplicateQuestions dt on dt.DuplicateQuestionId = ruw.PostId
left join (
    select
        UserId,
        count(*) as EditsCount,
        max(CreationDate) as LastEditDate
    from RecentPostHistoryEdits
    group by UserId
) ph on ph.UserId = tu.Id
left join RankedUserTags rut on rut.UserId = tu.Id and rut.TagRank = 1
left join RecursiveUserBadges rub on rub.UserId = tu.Id and rub.BadgeRank = 1
where (rut.Tag is not null or dt.DuplicateQuestionId is not null)
order by tu.Reputation desc, ph.EditsCount desc
limit 100;