-- {"query": "983.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2173} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        array[t.TagName] as TagPath,
        1 as Level
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        r.TagPath || t.TagName,
        r.Level + 1
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id
    where r.Level < 3
),
UserBadgeAgg as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PostStats as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.AcceptedAnswerId,
        coalesce((select count(*) from Comments c where c.PostId = p.Id), 0) as CommentCount,
        coalesce((select max(ph.CreationDate) from PostHistory ph where ph.PostId = p.Id), p.CreationDate) as LastEditDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as UserTopPostRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
AnswerDetails as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.OwnerUserId as AnswerOwnerUserId,
        u.Reputation as AnswererReputation,
        u.DisplayName as AnswererDisplayName,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as AnswerUpVotes,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3) as AnswerDownVotes
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
QuestionDetails as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.OwnerUserId as QuestionOwnerUserId,
        u.Reputation as QuestionOwnerReputation,
        u.DisplayName as QuestionOwnerDisplayName,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViewCount,
        q.Tags,
        q.AnswerCount,
        q.AcceptedAnswerId,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as QuestionUpVotes,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 3) as QuestionDownVotes,
        (select count(*) from Comments c where c.PostId = q.Id) as QuestionCommentCount,
        case when q.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts q
    left join Users u on u.Id = q.OwnerUserId
    where q.PostTypeId = 1
),
QuestionAnswerJoin as (
    select
        qd.QuestionId,
        qd.Title,
        qd.QuestionCreationDate,
        qd.QuestionOwnerUserId,
        qd.QuestionOwnerReputation,
        qd.QuestionOwnerDisplayName,
        qd.QuestionScore,
        qd.QuestionViewCount,
        qd.Tags,
        qd.AnswerCount,
        qd.AcceptedAnswerId,
        qd.QuestionUpVotes,
        qd.QuestionDownVotes,
        qd.QuestionCommentCount,
        qd.IsClosed,
        ad.AnswerId,
        ad.AnswerScore,
        ad.AnswerCreationDate,
        ad.AnswerOwnerUserId,
        ad.AnswererReputation,
        ad.AnswererDisplayName,
        ad.AnswerUpVotes,
        ad.AnswerDownVotes,
        rank() over (partition by qd.QuestionId order by ad.AnswerScore desc, ad.AnswerCreationDate asc) as AnswerRank
    from QuestionDetails qd
    left join AnswerDetails ad on ad.QuestionId = qd.QuestionId
),
FilteredPosts as (
    select
        qaj.*
    from QuestionAnswerJoin qaj
    where qaj.AnswerRank = 1 or qaj.AnswerId is null
),
PostPopularity as (
    select
        fp.QuestionId,
        fp.Title,
        fp.QuestionOwnerUserId,
        fp.QuestionOwnerReputation,
        fp.QuestionOwnerDisplayName,
        fp.QuestionCreationDate,
        fp.QuestionScore,
        fp.QuestionViewCount,
        fp.AnswerCount,
        fp.AcceptedAnswerId,
        fp.IsClosed,
        fp.AnswerId,
        fp.AnswerScore,
        fp.AnswerCreationDate,
        fp.AnswerOwnerUserId,
        fp.AnswererReputation,
        fp.AnswererDisplayName,
        fp.AnswerUpVotes,
        fp.AnswerDownVotes,
        fp.QuestionUpVotes,
        fp.QuestionDownVotes,
        fp.QuestionCommentCount,
        case 
            when fp.AcceptedAnswerId = fp.AnswerId then 1
            else 0
        end as IsAcceptedAnswer,
        dense_rank() over (order by fp.QuestionScore desc, fp.QuestionViewCount desc) as PopularQuestionRank
    from FilteredPosts fp
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as NumQuestions,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as NumAnswers,
        count(distinct c.Id) as NumComments,
        sum(v.VoteTypeId in (2, 5)::int) as TotalUpVotes,
        sum(v.VoteTypeId = 3::int) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate,
        coalesce(uba.GoldBadges, 0) as GoldBadges,
        coalesce(uba.SilverBadges, 0) as SilverBadges,
        coalesce(uba.BronzeBadges, 0) as BronzeBadges,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join UserBadgeAgg uba on uba.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, uba.GoldBadges, uba.SilverBadges, uba.BronzeBadges
),
TagPostCounts as (
    select
        tag,
        count(*) as QuestionCount
    from (
        select unnest(string_to_array(substring(t.Tags from 2 for char_length(t.Tags) - 2), '><')) as tag
        from Posts t
        where t.PostTypeId = 1 and t.Tags is not null
    ) sub
    group by tag
),
PopularTagsWithQuestions as (
    select
        tpc.tag,
        tpc.QuestionCount,
        array_agg(q.Id order by q.Score desc limit 3) as TopQuestionIds
    from TagPostCounts tpc
    join Posts q on q.PostTypeId = 1 and q.Tags like concat('%<', tpc.tag, '>%')
    group by tpc.tag, tpc.QuestionCount
    order by tpc.QuestionCount desc
    limit 10
)
select
    pp.PopularQuestionRank,
    pp.QuestionId,
    pp.Title,
    ua.DisplayName as QuestionOwner,
    ua.Reputation as OwnerReputation,
    pp.QuestionScore,
    pp.QuestionViewCount,
    pp.AnswerId,
    pp.AnswerScore,
    apt.DisplayName as AnswerOwner,
    apt.Reputation as AnswerOwnerReputation,
    pp.IsAcceptedAnswer,
    pp.IsClosed,
    pp.QuestionUpVotes,
    pp.QuestionDownVotes,
    pp.QuestionCommentCount,
    ua.NumQuestions,
    ua.NumAnswers,
    ua.NumComments,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    pt.tag as PopularTag,
    pt.QuestionCount as TagQuestionCount,
    string_agg(distinct coalesce(pht.Name, 'Unknown') || ':' || ph.Text, '; ') as RecentPostHistoryDetails
from PostPopularity pp
left join UserActivity ua on ua.UserId = pp.QuestionOwnerUserId
left join UserActivity apt on apt.UserId = pp.AnswerOwnerUserId
left join PopularTagsWithQuestions pt on pt.TopQuestionIds @> array[pp.QuestionId]
left join PostHistory ph on ph.PostId = pp.QuestionId and ph.CreationDate > pp.QuestionCreationDate - interval '30 days'
left join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
where ua.Reputation > 1000
group by 
    pp.PopularQuestionRank,
    pp.QuestionId,
    pp.Title,
    ua.DisplayName,
    ua.Reputation,
    pp.QuestionScore,
    pp.QuestionViewCount,
    pp.AnswerId,
    pp.AnswerScore,
    apt.DisplayName,
    apt.Reputation,
    pp.IsAcceptedAnswer,
    pp.IsClosed,
    pp.QuestionUpVotes,
    pp.QuestionDownVotes,
    pp.QuestionCommentCount,
    ua.NumQuestions,
    ua.NumAnswers,
    ua.NumComments,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    pt.tag,
    pt.QuestionCount
order by pp.PopularQuestionRank
limit 50;