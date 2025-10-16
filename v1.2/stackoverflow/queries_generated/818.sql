-- {"query": "818.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1309} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
FilteredPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        p.Title,
        p.AcceptedAnswerId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.DisplayName as OwnerDisplayName,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        (select max(ph.CreationDate) from PostHistory ph where ph.PostId = p.Id) as LastHistoryDate
    from Posts p
    join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2)
      and p.Score >= 10
      and p.CreationDate > '2019-01-01'
),
UserBadgeStats as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostComments as (
    select 
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct c.UserDisplayName, ', ') as Commenters
    from Comments c
    group by c.PostId
),
DuplicateLinks as (
    select 
        pl.PostId,
        count(*) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        string_agg(distinct p2.Title, ' | ') as DuplicateTitles
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    left join Posts p2 on pl.RelatedPostId = p2.Id
    group by pl.PostId
),
RankedAnswers as (
    select 
        p.Id,
        p.ParentId,
        p.Score,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
),
TopAnswerStats as (
    select 
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.AnswerRank,
        u.DisplayName as AnswerOwner,
        u.Reputation as AnswerOwnerRep
    from RankedAnswers a
    join Users u on a.OwnerUserId = u.Id
    where a.AnswerRank = 1
),
QuestionWithTopAnswer as (
    select 
        fp.Id as QuestionId,
        fp.Title,
        fp.Tags,
        fp.Score as QuestionScore,
        fp.ViewCount,
        fp.CreationDate as QuestionCreationDate,
        fp.OwnerUserId,
        fp.OwnerDisplayName,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        pc.CommentCount,
        pc.LastCommentDate,
        pc.Commenters,
        dl.DuplicateCount,
        dl.DuplicateTitles,
        ta.AnswerId,
        ta.AnswerScore,
        ta.AnswerOwner,
        ta.AnswerOwnerRep
    from FilteredPosts fp
    left join UserBadgeStats us on fp.OwnerUserId = us.UserId
    left join PostComments pc on fp.Id = pc.PostId
    left join DuplicateLinks dl on fp.Id = dl.PostId
    left join TopAnswerStats ta on fp.Id = ta.QuestionId
    where fp.PostTypeId = 1
),
FinalRanking as (
    select 
        q.*,
        dense_rank() over (
            partition by coalesce(nullif(substring(q.Tags from '<([^>]+)>'), ''), 'unknown')
            order by q.QuestionScore desc, q.ViewCount desc, q.AnswerScore desc nulls last
        ) as TagRank
    from QuestionWithTopAnswer q
)
select 
    fr.QuestionId,
    fr.Title,
    fr.Tags,
    fr.QuestionScore,
    fr.ViewCount,
    fr.QuestionCreationDate,
    coalesce(fr.OwnerDisplayName, 'Unknown') as QuestionOwner,
    coalesce(fr.GoldBadges, 0) as GoldBadges,
    coalesce(fr.SilverBadges, 0) as SilverBadges,
    coalesce(fr.BronzeBadges, 0) as BronzeBadges,
    fr.CommentCount,
    fr.LastCommentDate,
    substring(fr.Commenters from 1 for 100) as CommentersSample,
    fr.DuplicateCount,
    fr.DuplicateTitles,
    fr.AnswerId,
    fr.AnswerScore,
    fr.AnswerOwner,
    fr.AnswerOwnerRep,
    fr.TagRank,
    case 
        when fr.ClosedDate is not null then 'Closed'
        when fr.Score > 100 then 'Hot'
        else 'Normal'
    end as QuestionStatus,
    length(fr.Title) as TitleLength,
    length(coalesce(fr.Tags, '')) as TagsLength
from FinalRanking fr
where fr.TagRank <= 10
order by fr.TagRank, fr.QuestionScore desc, fr.ViewCount desc
limit 50;